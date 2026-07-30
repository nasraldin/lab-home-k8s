#!/usr/bin/env bash
# Create / document lab LXCs on pve01 via pct (when Terraform API is flaky).
# Target IDs align with last-octet (1xx). Jumpbox is ssh-01 — not infra.
# Run on Mac: ssh root@192.168.68.13 'bash -s' < terraform/scripts/pct-create-restructure-lxcs.sh
set -euo pipefail

NODE_SSH_KEY="${NODE_SSH_KEY:-ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH9wRDs8478+qe0aQk1Cfwv98FHoByrmWLP63Rngbn/G pve01.lab.nasraldin.com}"
TEMPLATE="${TEMPLATE:-local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst}"
STORAGE="${STORAGE:-data01}"
BRIDGE="${BRIDGE:-vmbr0}"
GW="${GW:-192.168.68.1}"

create_ct() {
  local vmid="$1" name="$2" ip="$3" memory="$4" disk="$5" cores="$6" tags="$7"
  if pct status "$vmid" &>/dev/null; then
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
      --tags "$tags" \
      --ssh-public-keys <(printf '%s\n' "$NODE_SSH_KEY") \
      --start 1
  fi
}

# Technitium authoritative — ID 111 = .11
create_ct 111 dns-01 192.168.68.11 512 10 1 "dns;technitium;core"
pct set 111 --startup order=2,up=10 || true

# Jumpbox — ssh-01 at .12 (NOT infra)
create_ct 112 ssh-01 192.168.68.12 2048 20 2 "ssh;jumpbox;core"
pct set 112 --startup order=3,up=10 || true

# AdGuard recursive DNS — .14 (PVE is .13); DHCP Primary
create_ct 114 adguard-01 192.168.68.14 512 10 1 "dns;adguard;core"
pct set 114 --startup order=1,up=15 || true

# Infisical
create_ct 125 infisical-01 192.168.68.25 4096 40 2 "infisical;secrets;core"
pct set 125 --startup order=12 || true

echo "Done. llm-01 (126/.26) is GPU/privileged — create via Terraform or manual pct with device passthrough."
pct list
