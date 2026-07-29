#!/usr/bin/env bash
# Shared helpers for k8s-lab bootstrap scripts.
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cluster() {
  need_cmd kubectl
  kubectl cluster-info >/dev/null
}
