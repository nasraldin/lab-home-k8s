#!/usr/bin/env bash
# Manual etcd snapshot (same logic as cron on control planes).
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/etcd}"
RETAIN_DAYS="${RETAIN_DAYS:-7}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${BACKUP_DIR}/etcd-${STAMP}.db"

export ETCDCTL_API=3
if ! command -v etcdctl >/dev/null 2>&1; then
  echo "etcdctl not found — install etcd-client on the control plane" >&2
  exit 1
fi

mkdir -p "${BACKUP_DIR}"
etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save "${OUT}"
chmod 600 "${OUT}"
find "${BACKUP_DIR}" -type f -name 'etcd-*.db' -mtime +"${RETAIN_DAYS}" -delete
echo "Saved ${OUT}"
