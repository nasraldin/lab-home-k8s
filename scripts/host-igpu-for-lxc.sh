#!/usr/bin/env bash
# Prepare pve01 iGPU for LXC device passthrough (llm-01).
#
# Opposite of the ai-01 VFIO path: host must load amdgpu and expose
# /dev/dri/renderD128 + /dev/kfd. Do NOT live-rebind after VFIO — that can
# hard-hang the node. Always: stop VM → disable vfio conf → reboot → verify.
set -euo pipefail

AI_VMID="${AI_VMID:-120}"
VFIO_CONF="${VFIO_CONF:-/etc/modprobe.d/vfio-amd-igpu.conf}"
VFIO_DISABLED="${VFIO_CONF}.disabled-for-lxc"

if [[ "$(hostname -s)" != "pve01" && "${FORCE_HOST:-}" != "1" ]]; then
  echo "Run on pve01 (or FORCE_HOST=1)." >&2
  exit 1
fi

echo "==> Stop ai-01 (VMID ${AI_VMID}); keep disk; clear hostpci; disable onboot"
qm set "${AI_VMID}" --onboot 0 || true
if qm status "${AI_VMID}" 2>/dev/null | grep -q running; then
  qm stop "${AI_VMID}" --timeout 120 || true
fi
qm set "${AI_VMID}" --delete hostpci0 2>/dev/null || true

echo "==> Disable VFIO id bind + amdgpu blacklist (persist)"
if [[ -f "${VFIO_CONF}" ]]; then
  mv -f "${VFIO_CONF}" "${VFIO_DISABLED}"
  echo "renamed ${VFIO_CONF} → ${VFIO_DISABLED}"
elif [[ -f "${VFIO_DISABLED}" ]]; then
  echo "already disabled (${VFIO_DISABLED})"
else
  echo "no VFIO conf found (OK if never enabled)"
fi

if [[ -e /dev/dri/renderD128 && -e /dev/kfd ]]; then
  echo "==> Host devices already present:"
  ls -la /dev/dri /dev/kfd
  lspci -nnk -s c6:00.0 || true
  echo "OK: ready for llm-01 device passthrough."
  exit 0
fi

echo
echo "NOTE: /dev/dri not ready yet. A reboot is required after disabling VFIO."
echo "      Do NOT echo the BDF into amdgpu/bind while the host is up — that can hang pve01."
echo
echo "Next:"
echo "  1) reboot   # or: systemctl reboot"
echo "  2) ssh pve01 'ls -la /dev/dri /dev/kfd; lspci -nnk -s c6:00.0'"
echo "     Expect: Kernel driver in use: amdgpu, and renderD128 + kfd present"
echo "  3) cd ~/homelab/lab-home-k8s/terraform && terraform apply"
echo "  4) ansible-playbook playbooks/ollama.yml"
exit 3
