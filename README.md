# lab-home-k8s

Infrastructure and Kubernetes for the **Dev Homelab** — one physical Proxmox host,
single control-plane kubeadm cluster (1 CP + 3 workers), plus core guests.
Day-2 platform apps live in [`lab-home-gitops`](https://github.com/nasraldin/lab-home-gitops).

**Documentation:** https://nasraldin.github.io/dev-homelab/ · monorepo ops:
[`docs/operations/lab-home-inventory.md`](../docs/operations/lab-home-inventory.md)

Secrets pointer map (gitignored, **no live passwords**): `lab-home-k8s/CREDENTIALS.md`.
Canonical secret store: `ansible/secrets.yml` + Infisical on `.25`.

## Topology (live — VMIDs 111–120, IPs unchanged)

| VMID/CTID   | Host           | IP              | Role                                                                               |
| ----------- | -------------- | --------------- | ---------------------------------------------------------------------------------- |
| **111**     | `dns-01`       | `.11`           | Technitium authoritative — 512M/10G LXC                                            |
| **112**     | `adguard-01`   | `.14`           | AdGuard (DHCP Primary) — 512M/10G LXC                                              |
| —           | `pve01`        | `192.168.68.13` | Proxmox (fixed)                                                                    |
| **113**     | `gitlab-01`    | `.15`           | GitLab CE                                                                          |
| **114**     | `runner-01`    | `.16`           | Host GitLab Runner                                                                 |
| **115**     | `k8s-cp-01`    | `.17`           | Control plane                                                                      |
| **116–118** | `k8s-w-01..03` | `.18–.20`       | Workers + Longhorn data disks                                                      |
| **119**     | `docker-01`    | `.21`           | **All** Docker apps: NPM, Stalwart, AIStor, Dockhand, Portainer, it-tools, mailpit |
| **120**     | `infisical-01` | `.25`           | Infisical + Postgres + Redis                                                       |

Destroyed: VM **110** (fat infra), old Dockhand/Portainer LXCs, VM **`ai-01`**,
jumpbox **`ssh-01`** (CT 112), Ollama **`llm-01`** (CT 126). SSH directly to
guests — no bastion.

API: `192.168.68.17:6443`. Cilium LB pool: `192.168.68.100–119`.

Cutover runbook: [lab-restructure-2026-07-30](../docs/operations/lab-restructure-2026-07-30.md).

### Kubernetes namespaces

Purpose-grouped NS (`ai-tools`, `observability`, `database`, `artifacts`,
`storage`, `security`, `gitops`, `apps`; keep `argocd`):
[`lab-home-gitops/docs/namespace-taxonomy.md`](../lab-home-gitops/docs/namespace-taxonomy.md).

## Ownership

| Concern                    | Path                                                                    |
| -------------------------- | ----------------------------------------------------------------------- |
| All VMs + LXC (Terraform)  | `terraform/`                                                            |
| Guest + k8s Ansible        | `ansible/`                                                              |
| Cilium + Argo CD bootstrap | `scripts/`                                                              |
| Platform apps (GitOps)     | [`lab-home-gitops`](https://github.com/nasraldin/lab-home-gitops)       |
| CI templates               | [`pipeline-templates`](https://github.com/nasraldin/pipeline-templates) |

## Documentation

| Topic                      | Link                                                                               |
| -------------------------- | ---------------------------------------------------------------------------------- |
| Inventory + cutover status | [lab-home-inventory](../docs/operations/lab-home-inventory.md)                     |
| Restructure sequence       | [lab-restructure-2026-07-30](../docs/operations/lab-restructure-2026-07-30.md)     |
| E2E reset checklist        | [docs/runbook/e2e-reset-checklist.md](docs/runbook/e2e-reset-checklist.md)         |
| Bring-up issues            | [docs/runbook/bring-up-issues-2026-07.md](docs/runbook/bring-up-issues-2026-07.md) |
| Daily use / public URLs    | [dev-homelab docs](https://nasraldin.github.io/dev-homelab/)                       |
