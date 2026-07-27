# lab-home-k8s

Infrastructure and Kubernetes for the **Dev Homelab** — one physical Proxmox host,
single control-plane kubeadm cluster (1 CP + 3 workers), plus core VM guests.
Day-2 platform apps live in [`lab-home-gitops`](https://github.com/nasraldin/lab-home-gitops).

**Documentation:** https://nasraldin.github.io/dev-homelab/

## Topology

| VMID    | Host              | IP        | Role                                   |
| ------- | ----------------- | --------- | -------------------------------------- |
| 110     | `infra-01`        | `.10`     | AdGuard, Technitium, Infisical, AIStor |
| 111     | `gitlab-01`       | `.11`     | GitLab CE                              |
| 112     | `runner-01`       | `.12`     | Static GitLab Runner                   |
| 113     | `k8s-cp-01`       | `.13`     | Control plane                          |
| 114–116 | `k8s-w-01..03`    | `.14–.16` | Workers + Longhorn data disks          |
| 117     | `docker-01`       | `.17`     | NPM, it-tools, mailpit                 |
| 118     | `dockhand` (LXC)  | `.18`     | Dockhand + Hawser hub                  |
| 119     | `portainer` (LXC) | `.19`     | Portainer CE (Docker management UI)    |

API: `192.168.68.13:6443` (direct to control plane — no HAProxy).

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
| Network, DNS, access            | [network and access](https://nasraldin.github.io/dev-homelab/architecture/network-and-access) |
| Fresh install                   | [bring-up runbook](https://nasraldin.github.io/dev-homelab/runbook/bring-up)                  |
| Public hostnames                | [public URLs](https://nasraldin.github.io/dev-homelab/access/public-urls)                     |
| LAN shortcuts                   | [LAN DNS](https://nasraldin.github.io/dev-homelab/access/lan-dns)                             |
| Kubeconfig                      | [laptop kubeconfig](https://nasraldin.github.io/dev-homelab/guide/kubeconfig)                 |
| Maintenance                     | [operations](https://nasraldin.github.io/dev-homelab/operations/maintenance)                  |

All documentation lives in the **[dev-homelab](https://github.com/nasraldin/dev-homelab)** repo — there is no `docs/` folder in this automation repo.

## Quickstart

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# edit tfvars + credentials.auto.tfvars

make tf-init
make tf-plan
make tf-apply
make ansible
make bootstrap
make verify
```

## Selective Ansible

```bash
make ansible-infra      # infra-01 only
make ansible-docker     # docker-01 only
make ansible-k8s        # k8s nodes only
```

## CI

`.gitlab-ci.yml` includes reusable jobs from `pipeline-templates`. Use
`TF_TARGET_GUESTS=infra-01` or `ANSIBLE_LIMIT=infra-01` for single-guest runs.
