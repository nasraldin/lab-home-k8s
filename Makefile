.PHONY: tf-init tf-adopt tf-plan tf-apply ansible ansible-infra ansible-gitlab ansible-docker ansible-k8s bootstrap verify docs

tf-init:
	cd terraform && terraform init

tf-adopt:
	cd terraform && ./scripts/adopt-existing.sh

tf-plan:
	cd terraform && terraform plan -out=tfplan

tf-apply:
	cd terraform && terraform apply tfplan

ansible:
	cd ansible && ansible-playbook -i inventory/hosts.yml playbooks/site.yml

ansible-infra:
	cd ansible && ansible-playbook -i inventory/hosts.yml playbooks/infra.yml

ansible-gitlab:
	cd ansible && ansible-playbook -i inventory/hosts.yml playbooks/gitlab.yml

ansible-docker:
	cd ansible && ansible-playbook -i inventory/hosts.yml playbooks/docker-hosts.yml

ansible-k8s:
	cd ansible && ansible-playbook -i inventory/hosts.yml playbooks/k8s.yml

bootstrap:
	./scripts/install-cilium.sh
	./scripts/install-argocd.sh

verify:
	./scripts/verify.sh

docs:
	@echo "Documentation: https://nasraldin.github.io/dev-homelab/"
