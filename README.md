# lab-home-k8s

Infrastructure and Kubernetes for the **Dev Homelab** — one physical Proxmox host,
single control-plane kubeadm cluster (1 CP + 3 workers), plus core VM guests.
Day-2 platform apps live in [`lab-home-gitops`](https://github.com/nasraldin/lab-home-gitops).

**Documentation:** https://nasraldin.github.io/dev-homelab/

## Topology

| VMID    | Host              | IP              | Role                                   |
| ------- | ----------------- | --------------- | -------------------------------------- |
| —       | `pve01`           | `192.168.68.13` | Proxmox (fixed)                        |
| 110     | `infra-01`        | `.14`           | AdGuard, Technitium, Infisical, AIStor |
| 111     | `gitlab-01`       | `.15`           | GitLab CE                              |
| 112     | `runner-01`       | `.16`           | Static GitLab Runner                   |
| 113     | `k8s-cp-01`       | `.17`           | Control plane                          |
| 114–116 | `k8s-w-01..03`    | `.18–.20`       | Workers + Longhorn data disks          |
| 117     | `docker-01`       | `.21`           | NPM, it-tools, mailpit                 |
| 118     | `dockhand` (LXC)  | `.22`           | Dockhand + Hawser hub                  |
| 119     | `portainer` (LXC) | `.23`           | Portainer CE (Docker management UI)    |
| 120     | `ai-01`           | `.24`           | Ollama + **gemma4:12b** (890M GPU PT)  |

API: `192.168.68.17:6443` (direct to control plane — no HAProxy).
Cilium LB pool: `192.168.68.100–119`.

Ollama on `ai-01` listens at `http://192.168.68.24:11434` (bind `0.0.0.0`).
AMD XDNA NPU cannot be VFIO’d — GPU only. Chat UIs (LibreChat, AnythingLLM, n8n,
Open WebUI) live in `lab-home-gitops` and call **LiteLLM** (`.108`); only LiteLLM
talks to Ollama.

**GPU passthrough (before first `ai-01` start):** host loses the iGPU while the guest owns it.

1. Kernel: `iommu=pt` (AMD-Vi) already expected via bootstrap.
2. Blacklist `amdgpu` on the host (and bind `1002:150e` to `vfio-pci`).
3. Confirm: `lspci -nnk -s c6:00.0` shows kernel driver `vfio-pci`.
4. Then Terraform-apply / start VMID `120` (**2 MiB hugepages** + NUMA; ballooning off).
   Guest: install Ollama, bind `OLLAMA_HOST=0.0.0.0:11434`, `ollama pull gemma4:12b`,
   open firewall for LAN `:11434`.
5. From a worker: `curl http://192.168.68.24:11434/api/tags` before syncing GitOps clients.

Docs: [ai-stack](https://nasraldin.github.io/dev-homelab/architecture/ai-stack) ·
[gpu-passthrough](https://nasraldin.github.io/dev-homelab/architecture/gpu-passthrough).

## Ownership

| Concern                    | Path                                                                    |
| -------------------------- | ----------------------------------------------------------------------- |
| All VMs + LXC (Terraform)  | `terraform/`                                                            |
| Guest + k8s Ansible        | `ansible/`                                                              |
| Cilium + Argo CD bootstrap | `scripts/`                                                              |
| Platform apps (GitOps)     | [`lab-home-gitops`](https://github.com/nasraldin/lab-home-gitops)       |
| CI templates               | [`pipeline-templates`](https://github.com/nasraldin/pipeline-templates) |
| Documentation              | [dev-homelab](https://nasraldin.github.io/dev-homelab/)                 |

## Documentation

| Topic                           | Link                                                                                          |
| ------------------------------- | --------------------------------------------------------------------------------------------- |
| **Daily use** (URLs, workflows) | [daily guide](https://nasraldin.github.io/dev-homelab/guide/daily-use)                        |
| **AI stack** (Ollama / LiteLLM) | [ai-stack](https://nasraldin.github.io/dev-homelab/architecture/ai-stack)                     |
| GPU passthrough                 | [gpu-passthrough](https://nasraldin.github.io/dev-homelab/architecture/gpu-passthrough)       |
| Network, DNS, access            | [network and access](https://nasraldin.github.io/dev-homelab/architecture/network-and-access) |
| Fresh install                   | [bring-up runbook](https://nasraldin.github.io/dev-homelab/runbook/bring-up)                  |
| Public hostnames                | [public URLs](https://nasraldin.github.io/dev-homelab/access/public-urls)                     |
| LAN shortcuts                   | [LAN DNS](https://nasraldin.github.io/dev-homelab/access/lan-dns)                             |
| Kubeconfig                      | [laptop kubeconfig](https://nasraldin.github.io/dev-homelab/guide/kubeconfig)                 |
| Maintenance                     | [operations](https://nasraldin.github.io/dev-homelab/operations/maintenance)                  |

All documentation lives in the **[dev-homelab](https://github.com/nasraldin/dev-homelab)** site.
Reset-specific notes: [`docs/runbook/bring-up-issues-2026-07.md`](docs/runbook/bring-up-issues-2026-07.md).

## Quickstart

Prerequisites: Proxmox host ready via `proxmox-bootstrap`, SSH as root works,
and local secrets filled in:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cp terraform/credentials.auto.tfvars.example terraform/credentials.auto.tfvars
cp ansible/secrets.example.yml ansible/secrets.yml
# Edit: zfs_pools device, ssh_public_key, proxmox_api_token, secrets.yml
# Place AIStor license: ansible/files/aistor/minio.license

# Optional local cheat-sheet (gitignored): CREDENTIALS.md
```

Canonical secrets: `ansible/secrets.yml` (gitignored). After Infisical is up,
seed projects with `ansible-playbook playbooks/infisical-seed.yml -e @secrets.yml`.
See [secrets docs](https://nasraldin.github.io/dev-homelab/architecture/secrets-and-infisical).

```bash
ssh-add ~/.ssh/pve01
ssh-copy-id root@pve01.lab.nasraldin.com
```

### Path A — Fresh Proxmox OS install

Nothing to adopt. Bootstrap the host, then go straight to Terraform:

```bash
make tf-init
make tf-plan
make tf-apply
# After GitLab is up: GITLAB_TOKEN=glpat-... ./scripts/seed-gitlab-gitops.sh
GITOPS_TOKEN=glpat-... make bring-up
```

### Path B — Factory-reset of an existing node

Factory-reset keeps Proxmox users/tokens and can leave residual GPT on the data
disk. Adopt those leftovers **before** plan/apply (skip this path after a fresh ISO):

```bash
make tf-init
cd terraform && ./scripts/adopt-existing.sh --check
make tf-adopt
# If plan fails on data01 "device already in use":
#   cd terraform && ./scripts/adopt-existing.sh --wipe-stale-zfs-disks

make tf-plan
make tf-apply
GITLAB_TOKEN=glpat-... ./scripts/seed-gitlab-gitops.sh
GITOPS_TOKEN=glpat-... make bring-up
```

### What Terraform creates (pve01 basics)

| Layer    | Resources                                                                |
| -------- | ------------------------------------------------------------------------ |
| Storage  | ZFS pool `data01`, `local` snippets/import, `local-backup` vzdump target |
| Images   | Debian 13 cloud image + LXC template                                     |
| Identity | OpsHub role/user/token/ACL (`opshub@pve!opshub`)                         |
| Backups  | Daily vzdump job (`02:00`, zstd, prune 7/4/3)                            |
| Guests   | 9 VMs (110–117, 120) + 2 LXC (118–119) — see topology table              |

## Selective Ansible

```bash
make ansible-infra      # infra-01 only
make ansible-docker     # docker-01 only
make ansible-k8s        # k8s nodes only
```

## CI

`.gitlab-ci.yml` includes reusable jobs from `pipeline-templates`. Use
`TF_TARGET_GUESTS=infra-01` or `ANSIBLE_LIMIT=infra-01` for single-guest runs.
