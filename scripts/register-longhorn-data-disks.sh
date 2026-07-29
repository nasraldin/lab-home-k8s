#!/usr/bin/env bash
# After ansible prepares /mnt/longhorn-data (live recovery) or /var/lib/longhorn
# (fresh), register the large disk on each Longhorn node and prefer it for
# scheduling. Safe to re-run.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/scripts/lib/common.sh"

need kubectl
need python3

MOUNT_CANDIDATES=("/var/lib/longhorn" "/mnt/longhorn-data")

echo "==> Registering Longhorn data disks on workers"

kubectl -n storage get nodes.longhorn.io -o name | while read -r node_ref; do
  node="${node_ref##*/}"
  echo "--- $node ---"
  # Resolve node InternalIP for SSH
  ip="$(kubectl get node "$node" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')"
  [[ -n "$ip" ]] || die "no InternalIP for $node"

  mount_path=""
  for cand in "${MOUNT_CANDIDATES[@]}"; do
    if ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 "nasr@${ip}" \
      "findmnt -n ${cand} >/dev/null 2>&1 && df -BG ${cand} | awk 'NR==2{gsub(/G/,\"\",\$2); if(\$2+0>=40) exit 0; exit 1}'"; then
      mount_path="$cand"
      break
    fi
  done
  if [[ -z "$mount_path" ]]; then
    echo "  skip: no large Longhorn mount found (run ansible k8s_longhorn_disk first)"
    continue
  fi
  echo "  using $mount_path"

  # Ensure Longhorn can write
  ssh -n -o StrictHostKeyChecking=no "nasr@${ip}" \
    "sudo mkdir -p ${mount_path}/replicas && sudo chmod 755 ${mount_path}"

  python3 - "$node" "$mount_path" <<'PY'
import json, subprocess, sys
node, path = sys.argv[1], sys.argv[2]
if not path.endswith("/"):
    path = path + "/"
raw = subprocess.check_output(
    ["kubectl", "-n", "storage", "get", "nodes.longhorn.io", node, "-o", "json"],
    text=True,
)
doc = json.loads(raw)
disks = doc.setdefault("spec", {}).setdefault("disks", {})

# Prefer data disk; keep default disk but stop scheduling onto root once data disk exists.
data_name = "data-disk"
if data_name not in disks:
    # copy tags from default-disk if present
    proto = next(iter(disks.values()), {})
    disks[data_name] = {
        "allowScheduling": True,
        "evictionRequested": False,
        "path": path,
        "storageReserved": 0,
        "tags": list(proto.get("tags") or []),
    }
else:
    disks[data_name]["path"] = path
    disks[data_name]["allowScheduling"] = True

for name, d in disks.items():
    if name == data_name:
        continue
    # Disable scheduling on the OS-root Longhorn path once data disk is ready
    if d.get("path", "").rstrip("/") in ("/var/lib/longhorn",) and path.rstrip("/") != "/var/lib/longhorn":
        d["allowScheduling"] = False

subprocess.run(
    ["kubectl", "-n", "storage", "apply", "-f", "-"],
    input=json.dumps(doc),
    text=True,
    check=True,
)
print(f"  patched {node}: data-disk={path}")
PY
done

echo "==> Longhorn node disk summary"
kubectl -n storage get nodes.longhorn.io \
  -o custom-columns='NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status,SCHED:.spec.allowScheduling'
