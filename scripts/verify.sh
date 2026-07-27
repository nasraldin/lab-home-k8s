#!/usr/bin/env bash
# Acceptance-oriented cluster checks (exit non-zero on failure).
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_cluster
fail=0

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "OK  ${name}"
  else
    echo "FAIL ${name}" >&2
    fail=1
  fi
}

check "nodes Ready count >= 4" bash -c '[[ $(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready") -ge 4 ]]'
check "API via current kubeconfig" kubectl get --raw=/readyz >/dev/null
check "Cilium DaemonSet present" kubectl -n kube-system get ds cilium >/dev/null 2>&1
check "Gateway API CRD" kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1
check "Cilium LB pool" kubectl get ciliumloadbalancerippool lab-pool >/dev/null 2>&1
check "Argo CD namespace" kubectl get ns argocd >/dev/null 2>&1
check "Argo CD server deploy" kubectl -n argocd get deploy argocd-server >/dev/null 2>&1

exit "${fail}"
