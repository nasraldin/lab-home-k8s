#!/usr/bin/env bash
# Apply day-0 Kubernetes Secrets so platform apps can start before Infisical
# machine-identity sync is configured. Idempotent (kubectl apply).
#
# Source of truth: lab-home-k8s/ansible/secrets.yml
# Later: InfisicalSecret CRs can overwrite the same secret names.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_FILE="${SECRETS_FILE:-${ROOT}/ansible/secrets.yml}"

require_cluster
need_cmd python3
need_cmd kubectl

[[ -f "${SECRETS_FILE}" ]] || die "missing ${SECRETS_FILE}"

# Export selected vault_* keys into the environment (values may contain special chars).
# Pre-declare so shellcheck knows these are assigned via eval.
declare vault_grafana_admin_password vault_harbor_admin_password vault_keycloak_admin_password
declare vault_keycloak_db_password vault_sonarqube_db_password vault_postgres_password
declare vault_librechat_creds_iv vault_librechat_creds_key vault_librechat_jwt_refresh_secret
declare vault_librechat_jwt_secret vault_librechat_meili_master_key vault_litellm_master_key
declare vault_litellm_postgres_password vault_litellm_postgres_user_password vault_n8n_encryption_key
declare vault_openclaw_gateway_token
eval "$(
  SECRETS_FILE="${SECRETS_FILE}" python3 - <<'PY'
import os, shlex, yaml
from pathlib import Path
s = yaml.safe_load(Path(os.environ["SECRETS_FILE"]).read_text())
keys = [
  "vault_grafana_admin_password",
  "vault_harbor_admin_password",
  "vault_keycloak_admin_password",
  "vault_keycloak_db_password",
  "vault_sonarqube_db_password",
  "vault_postgres_password",
  "vault_librechat_creds_iv",
  "vault_librechat_creds_key",
  "vault_librechat_jwt_refresh_secret",
  "vault_librechat_jwt_secret",
  "vault_librechat_meili_master_key",
  "vault_litellm_master_key",
  "vault_n8n_encryption_key",
  "vault_openclaw_gateway_token",
]
optional = [
  "vault_litellm_postgres_password",
  "vault_litellm_postgres_user_password",
]
for k in keys:
  v = s.get(k)
  if not v:
    raise SystemExit(f"missing {k} in secrets.yml")
  print(f"export {k}={shlex.quote(str(v))}")
for k in optional:
  v = s.get(k) or s.get("vault_postgres_password")
  print(f"export {k}={shlex.quote(str(v))}")
PY
)"

echo "==> Ensuring namespaces (see lab-home-gitops docs/namespace-taxonomy.md)"
for ns in ai-tools observability database artifacts storage security gitops apps; do
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -
done

echo "==> CNPG superuser + role password secrets (namespace database)"
kubectl -n database create secret generic postgres-superuser \
  --from-literal=username=postgres \
  --from-literal=password="${vault_postgres_password}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n database create secret generic cnpg-role-keycloak \
  --from-literal=username=keycloak \
  --from-literal=password="${vault_keycloak_db_password}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n database create secret generic cnpg-role-sonar \
  --from-literal=username=sonar \
  --from-literal=password="${vault_sonarqube_db_password}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> App secrets (Keycloak / Sonar in apps; Harbor in artifacts; Grafana)"
kubectl -n apps create secret generic keycloak-admin \
  --from-literal=admin-password="${vault_keycloak_admin_password}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n apps create secret generic keycloak-db \
  --from-literal=password="${vault_keycloak_db_password}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n apps create secret generic sonarqube-db \
  --from-literal=password="${vault_sonarqube_db_password}" \
  --from-literal=jdbc-password="${vault_sonarqube_db_password}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n artifacts create secret generic harbor-admin \
  --from-literal=HARBOR_ADMIN_PASSWORD="${vault_harbor_admin_password}" \
  --from-literal=password="${vault_harbor_admin_password}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n observability create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="${vault_grafana_admin_password}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> AI tools secrets (LibreChat / LiteLLM / n8n / OpenClaw)"
# Infisical universal-auth is often still missing after remap; these keep apps Ready.
# litellm-secrets holds Postgres passwords ONLY (mounted by Bitnami subchart).
# PROXY_MASTER_KEY also lives here for Infisical parity, but LiteLLM must NOT
# envFrom this secret (see apps/litellm/apps.yaml environmentSecrets: []).
kubectl -n ai-tools create secret generic librechat-env \
  --from-literal=CREDS_IV="${vault_librechat_creds_iv}" \
  --from-literal=CREDS_KEY="${vault_librechat_creds_key}" \
  --from-literal=JWT_REFRESH_SECRET="${vault_librechat_jwt_refresh_secret}" \
  --from-literal=JWT_SECRET="${vault_librechat_jwt_secret}" \
  --from-literal=MEILI_MASTER_KEY="${vault_librechat_meili_master_key}" \
  --from-literal=LITELLM_API_KEY="${vault_litellm_master_key}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n ai-tools create secret generic litellm-secrets \
  --from-literal=PROXY_MASTER_KEY="${vault_litellm_master_key}" \
  --from-literal=POSTGRES_PASSWORD="${vault_litellm_postgres_password}" \
  --from-literal=POSTGRES_USER_PASSWORD="${vault_litellm_postgres_user_password}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n ai-tools create secret generic litellm-masterkey \
  --from-literal=masterkey="${vault_litellm_master_key}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n ai-tools create secret generic litellm-dbcredentials \
  --from-literal=username=litellm \
  --from-literal=password="${vault_litellm_postgres_user_password}" \
  --from-literal=postgres-password="${vault_litellm_postgres_password}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n ai-tools create secret generic n8n-secrets \
  --from-literal=N8N_ENCRYPTION_KEY="${vault_n8n_encryption_key}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n ai-tools create secret generic n8n-app-secret \
  --from-literal=N8N_ENCRYPTION_KEY="${vault_n8n_encryption_key}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n ai-tools create secret generic openclaw-secrets \
  --from-literal=OPENCLAW_GATEWAY_TOKEN="${vault_openclaw_gateway_token}" \
  --from-literal=LITELLM_API_KEY="${vault_litellm_master_key}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Done. Optional later: create infisical-universal-auth in namespace security (see runbook)."
