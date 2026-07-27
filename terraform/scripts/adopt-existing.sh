#!/usr/bin/env bash
# lab-home-k8s/terraform/scripts/adopt-existing.sh
#
# After a factory-reset that KEPT Proxmox users/tokens (default), or when a ZFS
# pool was destroyed but the disk still has GPT/zfs_member leftovers, empty
# Terraform state will try to create objects that already exist and fail.
#
# This script adopts those leftovers into state (and optionally wipes stale
# data-disk partition tables so proxmox_node_disk_zfs can recreate the pool).
#
# Usage:
#   ./scripts/adopt-existing.sh                 # import OpsHub role/user/token/ACL
#   ./scripts/adopt-existing.sh --wipe-stale-zfs-disks
#   ./scripts/adopt-existing.sh --check         # print what would happen
#
# Safe defaults:
#   - Never deletes OpsHub user/token/role (factory-reset also leaves them)
#   - Disk wipe only with --wipe-stale-zfs-disks and only for disks listed in
#     terraform.tfvars zfs_pools that are NOT members of an imported zpool
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CHECK_ONLY=0
WIPE_STALE=0

usage() {
  sed -n '2,20p' "$0"
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    --wipe-stale-zfs-disks) WIPE_STALE=1 ;;
    -h | --help) usage ;;
    *)
      echo "unknown argument: $arg (try --help)" >&2
      exit 1
      ;;
  esac
done

need_cmd() { command -v "$1" > /dev/null || {
  echo "missing required command: $1" >&2
  exit 1
}; }
need_cmd terraform
need_cmd ssh

# shellcheck disable=SC1091
[[ -f "$ROOT/../../proxmox-bootstrap/config.env" ]] && source "$ROOT/../../proxmox-bootstrap/config.env" || true

read_proxmox_host() {
  if [[ ! -f terraform.tfvars ]]; then
    return 1
  fi
  local endpoint
  endpoint="$(grep -E '^[[:space:]]*proxmox_endpoint[[:space:]]*=' terraform.tfvars | head -1 | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')"
  [[ -n "$endpoint" ]] || return 1
  echo "$endpoint" | sed -E 's|https?://([^:/]+).*|\1|'
}

PVE_HOST="${PVE_HOST:-$(read_proxmox_host || true)}"
PVE_HOST="${PVE_HOST:-pve01.lab.nasraldin.com}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/pve01}"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=8 -i "$SSH_KEY_PATH" "root@${PVE_HOST}")

echo "== adopt-existing (PVE ${PVE_HOST}) =="

state_has() {
  terraform state list 2> /dev/null | grep -qxF "$1"
}

pve_has_role() {
  "${SSH[@]}" pveum role list --output-format json 2> /dev/null |
    python3 -c 'import json,sys; roles=json.load(sys.stdin); sys.exit(0 if any(r.get("roleid")=="OpsHub" for r in roles) else 1)'
}

pve_has_user() {
  "${SSH[@]}" pveum user list --output-format json 2> /dev/null |
    python3 -c 'import json,sys; users=json.load(sys.stdin); sys.exit(0 if any(u.get("userid")=="opshub@pve" for u in users) else 1)'
}

pve_has_token() {
  "${SSH[@]}" pveum user token list opshub@pve --output-format json 2> /dev/null |
    python3 -c 'import json,sys; toks=json.load(sys.stdin); sys.exit(0 if any(t.get("tokenid")=="opshub" for t in toks) else 1)'
}

pve_has_acl() {
  "${SSH[@]}" pveum acl list --output-format json 2> /dev/null |
    python3 -c 'import json,sys; acls=json.load(sys.stdin); sys.exit(0 if any(a.get("path")=="/" and a.get("roleid")=="OpsHub" and a.get("ugid")=="opshub@pve" for a in acls) else 1)'
}

import_one() {
  local addr="$1" id="$2"
  if state_has "$addr"; then
    echo "[skip] already in state: ${addr}"
    return 0
  fi
  if [[ "$CHECK_ONLY" == 1 ]]; then
    echo "[check] would import ${addr}  <=  ${id}"
    return 0
  fi
  echo "[import] ${addr}  <=  ${id}"
  terraform import -input=false "$addr" "$id"
}

# --- OpsHub identity (kept across factory-reset by design) --------------------
echo
echo "-- OpsHub role / user / token / ACL --"
if pve_has_role; then
  import_one 'proxmox_virtual_environment_role.opshub[0]' 'OpsHub'
else
  echo "[info] role OpsHub not on node — Terraform will create it"
fi

if pve_has_user; then
  import_one 'proxmox_virtual_environment_user.opshub[0]' 'opshub@pve'
else
  echo "[info] user opshub@pve not on node — Terraform will create it"
fi

if pve_has_token; then
  import_one 'proxmox_user_token.opshub[0]' 'opshub@pve!opshub'
  echo "[note] token secret is not re-exported on import — keep your existing OpsHub PROXMOX token"
else
  echo "[info] token opshub@pve!opshub not on node — Terraform will create it"
fi

if pve_has_acl; then
  import_one 'proxmox_acl.opshub[0]' '/?opshub@pve?OpsHub'
else
  echo "[info] ACL / + OpsHub + opshub@pve not on node — Terraform will create it"
fi

# --- Stale ZFS data disks (pool gone, GPT leftovers block recreate) -----------
echo
echo "-- ZFS data disks --"
mapfile -t ZFS_DEVICES < <(awk '
  /^[[:space:]]*#/ { next }
  /^[[:space:]]*zfs_pools[[:space:]]*=/ { in_pools=1; next }
  in_pools && /^[[:space:]]*[a-zA-Z0-9_-]+[[:space:]]*=[[:space:]]*{/ { pool=$1; gsub(/=.*/,"",pool) }
  in_pools && /^[[:space:]]*}/ {
    if (pool != "") { pool=""; next }
    exit
  }
  in_pools && /device[[:space:]]*=/ {
    if (match($0, /"\/dev\/[^"]+"/)) {
      s = substr($0, RSTART+1, RLENGTH-2)
      print s
    }
  }
' terraform.tfvars)

if ((${#ZFS_DEVICES[@]} == 0)); then
  echo "[info] no zfs_pools.device entries found in terraform.tfvars"
else
  for dev in "${ZFS_DEVICES[@]}"; do
    echo "[disk] ${dev}"
    remote_info="$(
      "${SSH[@]}" "bash -s" << EOF
set -euo pipefail
dev='${dev}'
if [[ ! -e "\$dev" ]]; then
  echo "MISSING"
  exit 0
fi
real="\$(readlink -f "\$dev")"
base="\$(basename "\$real")"
if zpool status 2>/dev/null | grep -Fq "\$base"; then
  echo "IN_POOL"
  exit 0
fi
parts=\$(lsblk -nr -o NAME "\$real" 2>/dev/null | wc -l | tr -d ' ')
zfs_parts=\$(lsblk -nr -o FSTYPE "\$real" 2>/dev/null | grep -c zfs_member || true)
if [[ "\$zfs_parts" -gt 0 || "\$parts" -gt 1 ]]; then
  echo "STALE parts=\$parts zfs_member=\$zfs_parts real=\$real"
else
  echo "CLEAN real=\$real"
fi
EOF
    )"
    echo "       ${remote_info}"
    case "$remote_info" in
      MISSING) echo "       [warn] device path missing on node" ;;
      IN_POOL) echo "       [ok] already in an imported zpool — leave alone" ;;
      CLEAN*) echo "       [ok] ready for proxmox_node_disk_zfs create" ;;
      STALE*)
        if [[ "$WIPE_STALE" != 1 ]]; then
          echo "       [action needed] residual partitions block TF create"
          echo "                     re-run with: $0 --wipe-stale-zfs-disks"
        elif [[ "$CHECK_ONLY" == 1 ]]; then
          echo "       [check] would wipefs + sgdisk --zap-all on this disk"
        else
          echo "       [wipe] clearing partition table + filesystem signatures"
          "${SSH[@]}" "bash -s" << EOF
set -euo pipefail
dev='${dev}'
real="\$(readlink -f "\$dev")"
if zpool status 2>/dev/null | grep -q "\$(basename "\$real")"; then
  echo "refusing wipe — disk still referenced by zpool" >&2
  exit 1
fi
wipefs -a "\$real" || true
for p in "\$real"*; do
  [[ -b "\$p" ]] || continue
  [[ "\$p" == "\$real" ]] && continue
  wipefs -a "\$p" 2>/dev/null || true
done
command -v sgdisk >/dev/null && sgdisk --zap-all "\$real" || true
partprobe "\$real" 2>/dev/null || true
echo wiped "\$real"
EOF
          echo "       [ok] disk wiped — terraform can create the pool"
        fi
        ;;
    esac
  done
fi

echo
if [[ "$CHECK_ONLY" == 1 ]]; then
  echo "Dry-run only. Re-run without --check to apply imports/wipes."
else
  echo "Next: terraform plan && terraform apply"
fi
