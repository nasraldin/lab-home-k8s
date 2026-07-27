#!/usr/bin/env bash
# Build Terraform -target flags from TF_TARGET_GUESTS for GitLab CI / local use.
#
# Env:
#   TF_TARGET_GUESTS  Comma-separated keys from var.vms (e.g. infra01 or infra01,vault-01).
#                     Empty = full stack (no -target). NEVER filter for_each — that destroys others.
#   TF_TARGET_KIND    vm (default) | ct | all
#                     vm → module.vm["name"]
#                     ct → proxmox_virtual_environment_container.ct["name"]
#
# Usage:
#   eval "$(./scripts/ci-targets.sh)"
#   terraform plan ${TF_TARGET_FLAGS} -out=tfplan
#
# Examples:
#   TF_TARGET_GUESTS=infra01 ./scripts/ci-targets.sh
#   TF_TARGET_GUESTS=vault-01,vault-seal ./scripts/ci-targets.sh

set -euo pipefail

TF_TARGET_GUESTS="${TF_TARGET_GUESTS:-}"
TF_TARGET_KIND="${TF_TARGET_KIND:-vm}"

flags=()

if [[ -z "${TF_TARGET_GUESTS// /}" ]]; then
  # Full apply — intentional empty
  echo "export TF_TARGET_FLAGS=''"
  echo "export TF_TARGET_MODE='full'"
  exit 0
fi

IFS=',' read -ra guests <<<"${TF_TARGET_GUESTS}"
for raw in "${guests[@]}"; do
  g="$(echo "${raw}" | xargs)" # trim
  [[ -z "${g}" ]] && continue

  case "${TF_TARGET_KIND}" in
  vm)
    # module.vm is for_each = var.vms — address is module.vm["guest-name"]
    flags+=(-target="module.vm[\"${g}\"]")
    ;;
  ct)
    flags+=(-target="proxmox_virtual_environment_container.ct[\"${g}\"]")
    ;;
  all)
    flags+=(-target="module.vm[\"${g}\"]")
    flags+=(-target="proxmox_virtual_environment_container.ct[\"${g}\"]")
    ;;
  *)
    echo "error: unknown TF_TARGET_KIND=${TF_TARGET_KIND} (use vm, ct, or all)" >&2
    exit 1
    ;;
  esac
done

if [[ ${#flags[@]} -eq 0 ]]; then
  echo "error: TF_TARGET_GUESTS set but no valid guest names parsed" >&2
  exit 1
fi

# shell-escaped for eval
escaped=$(printf '%q ' "${flags[@]}")
echo "export TF_TARGET_FLAGS=${escaped}"
echo "export TF_TARGET_MODE='targeted'"
