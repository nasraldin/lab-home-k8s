#!/usr/bin/env bash
# Create / document lab LXCs on pve01 via pct (when Terraform API is flaky).
# VMIDs packed 111–120. No jumpbox / no dedicated LLM guest.
# Run on Mac: ssh root@192.168.68.13 'bash -s' < terraform/scripts/pct-create-restructure-lxcs.sh
set -euo pipefail

NODE_SSH_KEY="${NODE_SSH_KEY:-ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH9wRDs8478+qe0aQk1Cfwv98FHoByrmWLP63Rngbn/G pve01.lab.nasraldin.com}"
TEMPLATE="${TEMPLATE:-local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst}"
STORAGE="${STORAGE:-data01}"
BRIDGE="${BRIDGE:-vmbr0}"
GW="${GW:-192.168.68.1}"

create_ct() {
  local vmid="$1" name="$2" ip="$3" memory="$4" disk="$5" cores="$6"
  if pct status "$vmid" &> /dev/null; then
    echo "CT $vmid ($name) already exists — skip create"
  else
    echo "Creating CT $vmid ($name)…"
    pct create "$vmid" "$TEMPLATE" \
      --hostname "$name" \
      --cores "$cores" \
      --memory "$memory" \
      --swap 0 \
      --rootfs "${STORAGE}:${disk}" \
      --net0 "name=eth0,bridge=${BRIDGE},firewall=0,gw=${GW},ip=${ip}/22,type=veth" \
      --unprivileged 1 \
      --features nesting=1 \
      --ostype debian \
      --onboot 1 \
      --ssh-public-keys <(printf '%s\n' "$NODE_SSH_KEY") \
      --start 1
  fi
}

# Technitium authoritative
create_ct 111 dns-01 192.168.68.11 512 10 1
pct set 111 --startup order=2,up=10 || true

# AdGuard recursive DNS — IP stays .14 (PVE is .13)
create_ct 112 adguard-01 192.168.68.14 512 10 1
pct set 112 --startup order=1,up=15 || true

# Infisical
create_ct 120 infisical-01 192.168.68.25 4096 40 2
pct set 120 --startup order=12 || true

echo "Done. VMIDs 111–120. Do not recreate ssh-01 / llm-01."
pct list
