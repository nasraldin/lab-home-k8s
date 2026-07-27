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
]
for k in keys:
  v = s.get(k)
  if not v:
    raise SystemExit(f"missing {k} in secrets.yml")
  print(f"export {k}={shlex.quote(str(v))}")
PY
)"

echo "==> Ensuring namespaces"
for ns in data keycloak sonarqube harbor observability infisical-operator-system; do
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -
done

echo "==> CNPG superuser + role password secrets (namespace data)"
kubectl -n data create secret generic postgres-superuser \
  --from-literal=username=postgres \
  --from-literal=password="${vault_postgres_password}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n data create secret generic cnpg-role-keycloak \
  --from-literal=username=keycloak \
  --from-literal=password="${vault_keycloak_db_password}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n data create secret generic cnpg-role-sonar \
  --from-literal=username=sonar \
  --from-literal=password="${vault_sonarqube_db_password}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> App secrets (Keycloak / Sonar / Harbor / Grafana)"
kubectl -n keycloak create secret generic keycloak-admin \
  --from-literal=admin-password="${vault_keycloak_admin_password}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n keycloak create secret generic keycloak-db \
  --from-literal=password="${vault_keycloak_db_password}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n sonarqube create secret generic sonarqube-db \
  --from-literal=password="${vault_sonarqube_db_password}" \
  --from-literal=jdbc-password="${vault_sonarqube_db_password}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n harbor create secret generic harbor-admin \
  --from-literal=HARBOR_ADMIN_PASSWORD="${vault_harbor_admin_password}" \
  --from-literal=password="${vault_harbor_admin_password}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n observability create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="${vault_grafana_admin_password}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Done. Optional later: create infisical-universal-auth for InfisicalSecret CRs (see runbook)."
