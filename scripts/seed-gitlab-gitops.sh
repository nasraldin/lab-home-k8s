#!/usr/bin/env bash
# Seed GitLab with lab-home-gitops on a fresh Omnibus install (LAN only).
# Requires: curl, git, GITLAB_TOKEN (PAT with api + write_repository).
set -euo pipefail

GITLAB_URL="${GITLAB_URL:-http://192.168.68.15}"
GITLAB_TOKEN="${GITLAB_TOKEN:?set GITLAB_TOKEN to a GitLab PAT with api,write_repository}"
GROUP_PATH="${GROUP_PATH:-homelab}"
PROJECT_PATH="${PROJECT_PATH:-lab-home-gitops}"
SRC_DIR="${SRC_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lab-home-gitops" && pwd)}"
BRANCH="${BRANCH:-main}"

HDR=(-H "PRIVATE-TOKEN: ${GITLAB_TOKEN}")

echo "==> Ensuring group ${GROUP_PATH}"
if ! curl -sf "${HDR[@]}" "${GITLAB_URL}/api/v4/groups/${GROUP_PATH}" >/dev/null; then
  curl -sf "${HDR[@]}" -X POST "${GITLAB_URL}/api/v4/groups" \
    --data-urlencode "name=${GROUP_PATH}" \
    --data-urlencode "path=${GROUP_PATH}" \
    --data-urlencode "visibility=private" >/dev/null
fi
GROUP_ID="$(curl -sf "${HDR[@]}" "${GITLAB_URL}/api/v4/groups/${GROUP_PATH}" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')"

echo "==> Ensuring project ${GROUP_PATH}/${PROJECT_PATH}"
ENCODED="${GROUP_PATH}%2F${PROJECT_PATH}"
if ! curl -sf "${HDR[@]}" "${GITLAB_URL}/api/v4/projects/${ENCODED}" >/dev/null; then
  curl -sf "${HDR[@]}" -X POST "${GITLAB_URL}/api/v4/projects" \
    --data-urlencode "name=${PROJECT_PATH}" \
    --data-urlencode "path=${PROJECT_PATH}" \
    --data-urlencode "namespace_id=${GROUP_ID}" \
    --data-urlencode "visibility=private" >/dev/null
fi

REMOTE_URL="${GITLAB_URL}/${GROUP_PATH}/${PROJECT_PATH}.git"
PUSH_URL="http://oauth2:${GITLAB_TOKEN}@${GITLAB_URL#http://}/${GROUP_PATH}/${PROJECT_PATH}.git"

echo "==> Pushing ${SRC_DIR} → ${REMOTE_URL} (${BRANCH})"
cd "${SRC_DIR}"
git push --force-with-lease "${PUSH_URL}" "HEAD:${BRANCH}"

echo "==> Done. Use with Argo:"
echo "  GITOPS_REPO=${REMOTE_URL} GITOPS_TOKEN=... ./scripts/install-argocd.sh"
