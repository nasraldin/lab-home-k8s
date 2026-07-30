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

echo "Done. Creating privileged llm-01 (GPU device passthrough) as root@pam…"

# llm-01 — privileged Ubuntu; API tokens cannot set device passthrough (root@pam only).
LLM_TEMPLATE="${LLM_TEMPLATE:-local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"
if pct status 126 &>/dev/null; then
  echo "CT 126 (llm-01) already exists — skip create"
else
  printf '%s\n' "$NODE_SSH_KEY" > /tmp/llm01-ssh.pub
  pct create 126 "$LLM_TEMPLATE" \
    --hostname llm-01 \
    --cores 8 \
    --memory 24576 \
    --swap 0 \
    --rootfs "${STORAGE}:100" \
    --net0 "name=eth0,bridge=${BRIDGE},firewall=0,gw=${GW},ip=192.168.68.26/22,type=veth" \
    --unprivileged 0 \
    --features nesting=1 \
    --ostype ubuntu \
    --onboot 1 \
    --tags "ai;ollama;gpu;llm" \
    --ssh-public-keys /tmp/llm01-ssh.pub \
    --dev0 path=/dev/dri/renderD128,gid=44,mode=0666 \
    --dev1 path=/dev/dri/card1,gid=44,mode=0666 \
    --dev2 path=/dev/kfd,gid=993,mode=0666 \
    --startup order=13 \
    --start 1
  rm -f /tmp/llm01-ssh.pub
  # Ubuntu template may not bring up eth0 from LXC net0 alone — seed ifupdown.
  pct exec 126 -- bash -c '
    if ! ip -4 addr show eth0 2>/dev/null | grep -q "192.168.68.26"; then
      cat > /etc/network/interfaces <<IEOF
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet static
    address 192.168.68.26/22
    gateway 192.168.68.1
IEOF
      ip link set eth0 up
      ip addr add 192.168.68.26/22 dev eth0 2>/dev/null || true
      ip route replace default via 192.168.68.1
    fi
  ' || true
fi

echo "Import llm-01 into Terraform if missing:"
echo "  cd terraform && terraform import 'proxmox_virtual_environment_container.ct[\"llm-01\"]' pve01/126"
pct list
