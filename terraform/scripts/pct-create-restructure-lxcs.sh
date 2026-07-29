#!/usr/bin/env bash
# Create restructure LXCs on pve01 via pct (when Terraform API is flaky).
# Run on Mac: ssh root@192.168.68.13 'bash -s' < scripts/pct-create-restructure-lxcs.sh
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

# AdGuard recursive DNS — LAN primary after DHCP cutover
create_ct 121 adguard-01 192.168.68.10 512 10 1 "dns;adguard;core"
pct set 121 --startup order=1,up=15 || true

# Technitium authoritative
create_ct 122 dns-01 192.168.68.11 512 10 1 "dns;technitium;core"
pct set 122 --startup order=2,up=10 || true

# Infisical + Postgres + Redis
create_ct 123 infisical-01 192.168.68.25 4096 40 2 "infisical;secrets;core"
pct set 123 --startup order=12 || true

echo "Done. pct list:"
pct list
echo
echo "Next on Mac:"
echo "  cd ~/homelab/lab-home-k8s/ansible"
echo "  ssh-keyscan -H 192.168.68.10 192.168.68.11 192.168.68.25 >> ~/.ssh/known_hosts"
echo "  ansible-playbook playbooks/dns.yml -e @secrets.yml"
echo "  ansible-playbook playbooks/infisical.yml -e @secrets.yml"
