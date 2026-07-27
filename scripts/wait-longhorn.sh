#!/usr/bin/env bash
# Wait for Longhorn + default StorageClass before PVC-backed apps sync.
# Also verifies worker data disks are mounted (ansible role k8s_longhorn_disk).
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_cluster
TIMEOUT="${TIMEOUT:-600}"
MIN_DISK_GB="${MIN_LONGHORN_DISK_GB:-80}"

echo "==> Waiting for StorageClass longhorn (timeout ${TIMEOUT}s)"
deadline=$((SECONDS + TIMEOUT))
until kubectl get sc longhorn >/dev/null 2>&1; do
  if ((SECONDS >= deadline)); then
    die "StorageClass longhorn not present — is platform-longhorn syncing?"
  fi
  sleep 5
done

echo "==> Waiting for Longhorn manager DaemonSet Ready"
deadline=$((SECONDS + TIMEOUT))
until kubectl -n longhorn-system get ds longhorn-manager >/dev/null 2>&1; do
  if ((SECONDS >= deadline)); then
    die "longhorn-manager DaemonSet missing"
  fi
  sleep 5
done

kubectl -n longhorn-system rollout status ds/longhorn-manager --timeout="${TIMEOUT}s"

echo "==> Checking Longhorn node disks report >= ${MIN_DISK_GB}Gi available"
deadline=$((SECONDS + TIMEOUT))
while true; do
  ok=1
  while read -r node avail; do
    [[ -z "$node" ]] && continue
    # avail is bytes
    gb=$((avail / 1024 / 1024 / 1024))
    echo "  $node: ${gb}Gi available"
    if ((gb < MIN_DISK_GB)); then
      ok=0
    fi
  done < <(kubectl -n longhorn-system get nodes.longhorn.io -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.diskStatus.*.storageAvailable}{"\n"}{end}' 2>/dev/null || true)

  if ((ok == 1)); then
    # Ensure at least one worker reported
    count=$(kubectl -n longhorn-system get nodes.longhorn.io --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if ((count >= 1)); then
      break
    fi
  fi
  if ((SECONDS >= deadline)); then
    die "Longhorn disks too small (<${MIN_DISK_GB}Gi). Terraform data_disk_gb must be mounted at /var/lib/longhorn (ansible role k8s_longhorn_disk) BEFORE Longhorn installs."
  fi
  sleep 10
done

echo "==> Longhorn ready (StorageClass + managers + data disks)"
