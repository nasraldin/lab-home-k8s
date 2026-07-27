#!/usr/bin/env bash
# etcd restore drill helper — run on a recovered control-plane node.
# See https://nasraldin.github.io/dev-homelab/runbook/etcd-backup-restore
set -euo pipefail

SNAPSHOT="${1:-}"
if [[ -z "${SNAPSHOT}" || ! -f "${SNAPSHOT}" ]]; then
  echo "Usage: $0 /path/to/etcd-YYYYMMDD.db" >&2
  exit 1
fi

if ! command -v etcdutl >/dev/null 2>&1; then
  echo "etcdutl not found — install etcd-client package" >&2
  exit 1
fi

RESTORE_DIR="${RESTORE_DIR:-/var/lib/etcd-restore}"
echo "This will restore into ${RESTORE_DIR} from ${SNAPSHOT}"
echo "Follow https://nasraldin.github.io/dev-homelab/runbook/etcd-backup-restore — stop static pods, replace data dir, restart."
echo
mkdir -p "${RESTORE_DIR}"
etcdutl snapshot restore "${SNAPSHOT}" \
  --data-dir="${RESTORE_DIR}" \
  --name="$(hostname -s)" \
  --initial-cluster="$(hostname -s)=https://$(hostname -I | awk '{print $1}'):2380" \
  --initial-advertise-peer-urls="https://$(hostname -I | awk '{print $1}'):2380"

echo "Restore written to ${RESTORE_DIR}"
echo "Next: move into /var/lib/etcd per the runbook, then start etcd/apiserver static pods."
