#!/usr/bin/env bash
# Terraform plan/apply/destroy wrapper for GitLab CI (and local dry-runs).
#
# Env:
#   TF_ACTION           plan | apply | destroy   (default: plan)
#   TF_TARGET_GUESTS    see ci-targets.sh        (empty = full)
#   TF_AUTO_APPROVE     true|false               (default: false)
#   TF_ALLOW_FULL_DESTROY  true required for destroy with empty TF_TARGET_GUESTS
#
# Prerequisites: terraform init already done (CI before_script).
#
# Examples:
#   TF_ACTION=plan TF_TARGET_GUESTS=infra01 ./scripts/ci-run.sh
#   TF_ACTION=apply TF_TARGET_GUESTS=infra01 TF_AUTO_APPROVE=true ./scripts/ci-run.sh
#   TF_ACTION=destroy TF_TARGET_GUESTS=docker-01 TF_AUTO_APPROVE=true ./scripts/ci-run.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

TF_ACTION="${TF_ACTION:-plan}"
TF_AUTO_APPROVE="${TF_AUTO_APPROVE:-false}"

# shellcheck disable=SC1090
eval "$("${ROOT}/scripts/ci-targets.sh")"

echo "==> TF_ACTION=${TF_ACTION} TF_TARGET_MODE=${TF_TARGET_MODE} TF_TARGET_GUESTS=${TF_TARGET_GUESTS:-<all>}"

case "${TF_ACTION}" in
plan)
  # shellcheck disable=SC2086
  terraform plan ${TF_TARGET_FLAGS} -out=tfplan
  terraform show -no-color tfplan | tee tfplan.txt
  ;;
apply)
  if [[ -f tfplan ]]; then
    terraform apply -input=false tfplan
  else
    extra=(-input=false)
    [[ "${TF_AUTO_APPROVE}" == "true" ]] && extra+=(-auto-approve)
    # shellcheck disable=SC2086
    terraform apply "${extra[@]}" ${TF_TARGET_FLAGS}
  fi
  ;;
destroy)
  if [[ "${TF_TARGET_MODE}" != "targeted" && "${TF_ALLOW_FULL_DESTROY:-false}" != "true" ]]; then
    echo "error: refuse full destroy without TF_TARGET_GUESTS (safety)" >&2
    echo "  set TF_TARGET_GUESTS=<guest> or TF_ALLOW_FULL_DESTROY=true" >&2
    exit 1
  fi
  extra=(-input=false)
  [[ "${TF_AUTO_APPROVE}" == "true" ]] && extra+=(-auto-approve)
  # shellcheck disable=SC2086
  terraform destroy "${extra[@]}" ${TF_TARGET_FLAGS}
  ;;
*)
  echo "error: TF_ACTION must be plan|apply|destroy (got ${TF_ACTION})" >&2
  exit 1
  ;;
esac
