.PHONY: tf-init tf-adopt tf-plan tf-apply ansible ansible-infra ansible-gitlab ansible-docker ansible-k8s bootstrap bring-up verify docs

# Order for a clean reset: terraform apply → make bring-up
# bring-up = Ansible site + Cilium/Argo + verify (do not wait for Ready in Ansible;
# nodes become Ready only after Cilium).

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

bootstrap:
	./scripts/fetch-kubeconfig.sh
	K8S_API_HOST=$${K8S_API_HOST:-192.168.68.17} ./scripts/install-cilium.sh
	GITOPS_REPO=$${GITOPS_REPO:-http://192.168.68.15/homelab/lab-home-gitops.git} ./scripts/install-argocd.sh

bring-up: ansible bootstrap verify

verify:
	./scripts/verify.sh

docs:
	@echo "Documentation: https://nasraldin.github.io/dev-homelab/"
