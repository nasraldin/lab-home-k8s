#!/usr/bin/env bash
# One-shot Argo CD install; day-2 apps live in lab-home-gitops.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_cluster
need_cmd helm

# Prefer LAN GitLab during bring-up (public Tunnel may return 530 before CF is healthy).
# Override with GITOPS_REPO=https://gitlab.nasraldin.com/homelab/lab-home-gitops.git when Tunnel is up.
GITOPS_REPO="${GITOPS_REPO:-http://192.168.68.15/homelab/lab-home-gitops.git}"
ARGO_NS=argocd
REGISTER_REPO="${REGISTER_REPO:-true}"
ARGO_HOSTNAME="${ARGO_HOSTNAME:-argo.nasraldin.com}"
ARGO_LB_IP="${ARGO_LB_IP:-192.168.68.100}"
ARGO_PUBLIC_URL="${ARGO_PUBLIC_URL:-https://${ARGO_HOSTNAME}}"
# GitLab PAT / project token with read_repository (required for private GitOps repo).
# Do not fall back to `gh` — that targets GitHub and cannot authenticate GitLab.
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
  if [[ -z "${TOKEN}" ]]; then
    echo "ERROR: set GITOPS_TOKEN to a GitLab PAT/project token with read_repository" >&2
    echo "  Example: GITOPS_TOKEN=glpat-... GITOPS_REPO=${GITOPS_REPO} ./scripts/install-argocd.sh" >&2
    exit 1
  fi
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
  username: ${GITOPS_USERNAME:-oauth2}
  password: ${TOKEN}
EOF
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
