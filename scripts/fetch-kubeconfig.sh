#!/usr/bin/env bash
# Fetch HA lab admin kubeconfig and install it into ~/.kube/config
# so kubectl works anytime (no KUBECONFIG export needed).
set -euo pipefail

CP_HOST="${CP_HOST:-nasr@192.168.68.13}"
KUBE_DIR="${HOME}/.kube"
DEFAULT_CONFIG="${KUBE_DIR}/config"
STANDALONE="${KUBE_DIR}/home-lab.config"
API_DNS="${API_DNS:-192.168.68.13}"
API_VIP="${API_VIP:-192.168.68.13}"
CONTEXT_NAME="${CONTEXT_NAME:-home-lab}"
CLUSTER_NAME="${CLUSTER_NAME:-home-lab}"
USER_NAME="${USER_NAME:-home-lab-admin}"
SET_CURRENT="${SET_CURRENT:-true}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

need_cmd kubectl
need_cmd ssh
need_cmd python3

mkdir -p "${KUBE_DIR}"
chmod 700 "${KUBE_DIR}"

echo "==> Checking DNS for ${API_DNS}"
if command -v dig >/dev/null 2>&1; then
  resolved="$(dig +short "${API_DNS}" | head -1 || true)"
  echo "    resolved: ${resolved:-<empty>}"
  if [[ -n "${resolved}" && "${resolved}" != "${API_VIP}" ]]; then
    echo "WARN: expected ${API_VIP}; got ${resolved}. Fix lab DNS or /etc/hosts." >&2
  fi
fi

echo "==> Checking API VIP ${API_VIP}:6443"
if command -v nc >/dev/null 2>&1; then
  if ! nc -z -G 3 "${API_VIP}" 6443 2>/dev/null && ! nc -z -w 3 "${API_VIP}" 6443 2>/dev/null; then
    echo "ERROR: cannot reach ${API_VIP}:6443 from this laptop" >&2
    exit 1
  fi
fi

TMP="$(mktemp)"
MERGED="$(mktemp)"
trap 'rm -f "${TMP}" "${MERGED}"' EXIT

echo "==> Fetching admin.conf from ${CP_HOST}"
ssh "${CP_HOST}" 'sudo cat /etc/kubernetes/admin.conf' > "${TMP}"
chmod 600 "${TMP}"

# Rewrite HA server URL + stable local names (cluster/user/context).
python3 - "${TMP}" "${API_DNS}" "${CLUSTER_NAME}" "${USER_NAME}" "${CONTEXT_NAME}" <<'PY'
import re, sys

path, dns, cluster, user, context = sys.argv[1:6]
text = open(path).read()
text = re.sub(
    r"(server:\s*https://)[^:\s]+(:6443)",
    rf"\g<1>{dns}\2",
    text,
    count=1,
)

# Rename first (and typically only) cluster / user / context entries.
text = re.sub(
    r"(clusters:\n- cluster:\n(?:.*\n)*?  name:\s*)\S+",
    rf"\1{cluster}",
    text,
    count=1,
)
text = re.sub(
    r"(users:\n- name:\s*)\S+",
    rf"\1{user}",
    text,
    count=1,
)
text = re.sub(
    r"(contexts:\n- context:\n(?:.*\n)*?  name:\s*)\S+",
    rf"\1{context}",
    text,
    count=1,
)
text = re.sub(
    r"(current-context:\s*)\S+",
    rf"\1{context}",
    text,
    count=1,
)
# Context body references
text = re.sub(r"(^\s+cluster:\s*)\S+", rf"\1{cluster}", text, count=1, flags=re.M)
text = re.sub(r"(^\s+user:\s*)\S+", rf"\1{user}", text, count=1, flags=re.M)

open(path, "w").write(text)
PY

# Keep a standalone copy for reference / backups.
cp "${TMP}" "${STANDALONE}"
chmod 600 "${STANDALONE}"

# Drop previous lab entries from the default config (if any), then merge.
if [[ -f "${DEFAULT_CONFIG}" ]]; then
  echo "==> Backing up ${DEFAULT_CONFIG} -> ${DEFAULT_CONFIG}.bak"
  cp "${DEFAULT_CONFIG}" "${DEFAULT_CONFIG}.bak"
  chmod 600 "${DEFAULT_CONFIG}.bak"

  WORK="$(mktemp)"
  cp "${DEFAULT_CONFIG}" "${WORK}"
  chmod 600 "${WORK}"
  KUBECONFIG="${WORK}" kubectl config delete-context "${CONTEXT_NAME}" >/dev/null 2>&1 || true
  KUBECONFIG="${WORK}" kubectl config delete-cluster "${CLUSTER_NAME}" >/dev/null 2>&1 || true
  KUBECONFIG="${WORK}" kubectl config delete-user "${USER_NAME}" >/dev/null 2>&1 || true

  # If leftover broken current-context, clear it before merge.
  if ! KUBECONFIG="${WORK}" kubectl config current-context >/dev/null 2>&1; then
    KUBECONFIG="${WORK}" kubectl config unset current-context >/dev/null 2>&1 || true
  fi

  echo "==> Merging into ${DEFAULT_CONFIG}"
  KUBECONFIG="${WORK}:${TMP}" kubectl config view --flatten > "${MERGED}"
  rm -f "${WORK}"
else
  echo "==> Creating ${DEFAULT_CONFIG}"
  cp "${TMP}" "${MERGED}"
fi

chmod 600 "${MERGED}"
mv "${MERGED}" "${DEFAULT_CONFIG}"
MERGED="$(mktemp)"

unset KUBECONFIG
if [[ "${SET_CURRENT}" == "true" ]]; then
  kubectl config use-context "${CONTEXT_NAME}" >/dev/null
fi

echo "==> Installed context '${CONTEXT_NAME}' in ${DEFAULT_CONFIG}"
echo "==> Standalone copy: ${STANDALONE}"
echo
kubectl config get-contexts
echo
kubectl get --raw=/readyz
echo
kubectl get nodes -o wide
