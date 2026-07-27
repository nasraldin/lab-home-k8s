#!/usr/bin/env bash
# One-shot Argo CD install; day-2 apps live in lab-home-gitops.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_cluster
need_cmd helm

# HTTPS matches the working lab path (SSH deploy keys hit Argo agent issues here).
GITOPS_REPO="${GITOPS_REPO:-https://gitlab.nasraldin.com/homelab/lab-home-gitops.git}"
ARGO_NS=argocd
REGISTER_REPO="${REGISTER_REPO:-true}"
ARGO_HOSTNAME="${ARGO_HOSTNAME:-argo.nasraldin.com}"
ARGO_LB_IP="${ARGO_LB_IP:-192.168.68.100}"
ARGO_PUBLIC_URL="${ARGO_PUBLIC_URL:-https://${ARGO_HOSTNAME}}"

echo "==> Creating namespace ${ARGO_NS}"
kubectl create namespace "${ARGO_NS}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Adding Argo Helm repo"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update argo >/dev/null

echo "==> Installing Argo CD (${ARGO_PUBLIC_URL})"
helm upgrade --install argocd argo/argo-cd \
  --namespace "${ARGO_NS}" \
  --wait \
  --set server.service.type=LoadBalancer \
  --set "server.service.loadBalancerIP=${ARGO_LB_IP}" \
  --set server.ingress.enabled=false \
  --set configs.params."server\.insecure"=true \
  --set configs.cm."url"="${ARGO_PUBLIC_URL}"

echo "==> Waiting for Argo CD server"
kubectl -n "${ARGO_NS}" rollout status deploy/argocd-server --timeout=300s

if [[ "${REGISTER_REPO}" == "true" ]]; then
  echo "==> Registering private GitOps repo credential"
  TOKEN="${GITOPS_TOKEN:-}"
  if [[ -z "${TOKEN}" ]] && command -v gh >/dev/null 2>&1; then
    TOKEN="$(gh auth token 2>/dev/null || true)"
  fi
  if [[ -n "${TOKEN}" ]]; then
    kubectl -n "${ARGO_NS}" apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: repo-lab-home-gitops
  namespace: ${ARGO_NS}
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  name: lab-home-gitops
  url: ${GITOPS_REPO}
  username: ${GITOPS_USERNAME:-nasraldin}
  password: ${TOKEN}
EOF
  else
    echo "WARN: no GITOPS_TOKEN — create repo-lab-home-gitops Secret manually" >&2
  fi
fi

ROOT_APP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/argocd-root-app.yaml"
if [[ -f "${ROOT_APP}" ]]; then
  echo "==> Applying root Application"
  sed "s|REPO_URL_PLACEHOLDER|${GITOPS_REPO}|g" "${ROOT_APP}" | kubectl apply -f -
else
  echo "NOTE: create config/argocd-root-app.yaml or apply lab-home-gitops/bootstrap/root-app.yaml manually"
fi

echo "==> Initial admin password:"
kubectl -n "${ARGO_NS}" get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true
echo
echo "Platform apps (cert-manager, KEDA, Longhorn, Keycloak, SonarQube, …) sync from lab-home-gitops."
