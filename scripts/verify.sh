#!/usr/bin/env bash
# Acceptance checks for a healthy home-lab after terraform + bring-up.
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
check "root Application exists" kubectl -n argocd get app root >/dev/null 2>&1
check "StorageClass longhorn" kubectl get sc longhorn >/dev/null 2>&1
check "GitOps repo Secret" kubectl -n argocd get secret repo-lab-home-gitops >/dev/null 2>&1

# Soft checks (warn only) — apps may still be progressing after first sync.
warn() {
  local name="$1"
  shift
  if "$@"; then
    echo "OK  ${name}"
  else
    echo "WARN ${name}" >&2
  fi
}

warn "CNPG Cluster CRD" kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1
warn "postgres Cluster object" kubectl -n database get cluster postgres >/dev/null 2>&1
warn "Argo LB .100" bash -c 'kubectl -n argocd get svc argocd-server -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2>/dev/null | grep -q 192.168.68.100'
warn "no ComparisonError on root children" bash -c '
  bad=$(kubectl -n argocd get applications -o json 2>/dev/null \
    | python3 -c "import sys,json; apps=json.load(sys.stdin).get(\"items\",[]);
print(sum(1 for a in apps for c in (a.get(\"status\") or {}).get(\"conditions\") or [] if c.get(\"type\")==\"ComparisonError\"))")
  [[ "${bad:-1}" == "0" ]]
'

warn "no Kyverno PolicyViolation warnings (recent)" bash -c '
  count=$(kubectl get events -A --field-selector type=Warning 2>/dev/null \
    | rg -c "PolicyViolation" || true)
  count=${count:-0}
  [[ "$count" -lt 5 ]]
'

echo
if [[ "${fail}" -eq 0 ]]; then
  echo "verify: core checks passed"
else
  echo "verify: ${fail} core check(s) failed" >&2
fi
exit "${fail}"
