.PHONY: tf-init tf-adopt tf-plan tf-apply ansible ansible-infra ansible-gitlab ansible-docker ansible-k8s \
	seed-gitops bootstrap-secrets wait-longhorn bootstrap bring-up verify docs

# Clean reset order (see docs/runbook/e2e-reset-checklist.md):
#   1. terraform apply
#   2. make ansible
#   3. mint GitLab PAT → make seed-gitops
#   4. make bootstrap   (kubeconfig + Cilium + Argo + secrets)
#   5. make wait-longhorn && make verify
# Or: GITLAB_TOKEN=… GITOPS_TOKEN=… make bring-up

tf-init:
	cd terraform && terraform init

tf-adopt:
	cd terraform && ./scripts/adopt-existing.sh

tf-plan:
	cd terraform && terraform plan -out=tfplan

tf-apply:
	cd terraform && terraform apply tfplan

ansible:
	cd ansible && ansible-playbook -i inventory/hosts.yml playbooks/site.yml -e @secrets.yml

ansible-infra:
	cd ansible && ansible-playbook -i inventory/hosts.yml playbooks/infra.yml -e @secrets.yml

ansible-gitlab:
	cd ansible && ansible-playbook -i inventory/hosts.yml playbooks/gitlab.yml -e @secrets.yml

ansible-docker:
	cd ansible && ansible-playbook -i inventory/hosts.yml playbooks/docker-hosts.yml -e @secrets.yml

ansible-k8s:
	cd ansible && ansible-playbook -i inventory/hosts.yml playbooks/k8s.yml -e @secrets.yml

# Push local lab-home-gitops → LAN GitLab (requires GITLAB_TOKEN)
seed-gitops:
	./scripts/seed-gitlab-gitops.sh

# Day-0 secrets so Keycloak/Harbor/Grafana/CNPG work before Infisical identity
bootstrap-secrets:
	./scripts/apply-bootstrap-secrets.sh

wait-longhorn:
	./scripts/wait-longhorn.sh

bootstrap:
	./scripts/fetch-kubeconfig.sh
	K8S_API_HOST=$${K8S_API_HOST:-192.168.68.17} ./scripts/install-cilium.sh
	GITOPS_REPO=$${GITOPS_REPO:-http://192.168.68.15/homelab/lab-home-gitops.git} ./scripts/install-argocd.sh
	./scripts/apply-bootstrap-secrets.sh

# Full path after terraform apply. Requires GITLAB_TOKEN + GITOPS_TOKEN (same PAT is fine).
bring-up: ansible seed-gitops bootstrap wait-longhorn verify

verify:
	./scripts/verify.sh

docs:
	@echo "Runbook: docs/runbook/e2e-reset-checklist.md"
	@echo "Issues:  docs/runbook/bring-up-issues-2026-07.md"
	@echo "Site:    https://nasraldin.github.io/dev-homelab/"
