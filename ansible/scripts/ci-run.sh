#!/usr/bin/env bash
# Ansible playbook wrapper for GitLab CI (and local).
#
# Env:
#   ANSIBLE_PLAYBOOK   Path under repo root (default: playbooks/infra.yml)
#   ANSIBLE_LIMIT      Inventory host or group (empty = playbook hosts)
#   ANSIBLE_SECRETS    Path to secrets file (default: secrets.yml if present)
#   ANSIBLE_CHECK      true → --check (dry-run)
#
# Examples:
#   ANSIBLE_PLAYBOOK=playbooks/infra.yml ANSIBLE_LIMIT=infra01 ./scripts/ci-run.sh
#   ANSIBLE_PLAYBOOK=playbooks/dns.yml ANSIBLE_LIMIT=adguard-01 ./scripts/ci-run.sh
#   ANSIBLE_PLAYBOOK=playbooks/object-storage.yml ANSIBLE_LIMIT=vault-01 ./scripts/ci-run.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

ANSIBLE_PLAYBOOK="${ANSIBLE_PLAYBOOK:-playbooks/infra.yml}"
ANSIBLE_LIMIT="${ANSIBLE_LIMIT:-}"
ANSIBLE_SECRETS="${ANSIBLE_SECRETS:-}"
ANSIBLE_CHECK="${ANSIBLE_CHECK:-false}"

if [[ -z "${ANSIBLE_SECRETS}" ]]; then
  if [[ -f "${ROOT}/secrets.yml" ]]; then
    ANSIBLE_SECRETS="${ROOT}/secrets.yml"
  fi
fi

args=(ansible-playbook "${ANSIBLE_PLAYBOOK}")

if [[ -n "${ANSIBLE_LIMIT}" ]]; then
  args+=(--limit "${ANSIBLE_LIMIT}")
fi

if [[ -n "${ANSIBLE_SECRETS}" ]]; then
  if [[ ! -f "${ANSIBLE_SECRETS}" ]]; then
    echo "error: ANSIBLE_SECRETS file not found: ${ANSIBLE_SECRETS}" >&2
    exit 1
  fi
  args+=(-e "@${ANSIBLE_SECRETS}")
fi

if [[ "${ANSIBLE_CHECK}" == "true" ]]; then
  args+=(--check --diff)
fi

echo "==> ${args[*]}"
exec "${args[@]}"
