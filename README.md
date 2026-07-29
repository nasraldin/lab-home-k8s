# lab-home-k8s

Infrastructure and Kubernetes for the **Dev Homelab** — one physical Proxmox host,
single control-plane kubeadm cluster (1 CP + 3 workers), plus core guests.
Day-2 platform apps live in [`lab-home-gitops`](https://github.com/nasraldin/lab-home-gitops).

**Documentation:** https://nasraldin.github.io/dev-homelab/ · monorepo ops:
[`docs/operations/lab-home-inventory.md`](../docs/operations/lab-home-inventory.md)

## Topology (target after 2026-07-30 restructure)

| VMID/CTID | Host | IP | Role |
| --------- | ---- | -- | ---- |
| — | `pve01` | `192.168.68.13` | Proxmox (fixed) |
| **121** | `adguard-01` | `.10` | AdGuard (DHCP Primary) — 512M/10G LXC |
| **122** | `dns-01` | `.11` | Technitium authoritative — 512M/10G LXC |
| **110→124** | `infra-01` | `.14` | Fat VM until drain → **jumpbox LXC** only |
| **111** | `gitlab-01` | `.15` | GitLab CE |
| **112** | `runner-01` | `.16` | Host GitLab Runner |
| **113** | `k8s-cp-01` | `.17` | Control plane |
| **114–116** | `k8s-w-01..03` | `.18–.20` | Workers + Longhorn data disks |
| **117** | `docker-01` | `.21` | **All** Docker apps: NPM, Stalwart, AIStor, Dockhand, Portainer, it-tools, mailpit |
| **118/119** | dockhand / portainer LXCs | `.22`/`.23` | **Legacy** — retire after apps on docker-01 |
| **120** | `ai-01` | `.24` | **Standby** (former Ollama VFIO VM — do not delete yet) |
| **123** | `infisical-01` | `.25` | Infisical + Postgres + Redis |
| **125** | `llm-01` | `.26` | Ollama + ROCm userspace (`/dev/dri` + `/dev/kfd`) |

API: `192.168.68.17:6443`. Cilium LB pool: `192.168.68.100–119`.

Cutover runbook: [lab-restructure-2026-07-30](../docs/operations/lab-restructure-2026-07-30.md).
**Live cutover** may be **pending** if `pve01` was down — IaC targets are in tree.

### Ollama / GPU

Inference path: **clients → LiteLLM (`.108`) → Ollama on `llm-01` (`.26:11434`)**.

1. Host loads **`amdgpu`** (no VFIO bind): `scripts/host-igpu-for-lxc.sh` then **reboot**.
2. Confirm: `lspci -nnk -s c6:00.0` → `amdgpu`; `/dev/dri/renderD128` + `/dev/kfd`.
3. `terraform apply` (CT 125) → `ansible-playbook playbooks/ollama.yml`.
4. Verify GPU via `ollama ps` before decommissioning `ai-01`.

Docs: [ollama-llm-01](../docs/operations/ollama-llm-01.md).

### Kubernetes namespaces

Purpose-grouped NS (`ai-tools`, `observability`, `database`, `artifacts`,
`storage`, `security`, `gitops`, `apps`; keep `argocd`):
[`lab-home-gitops/docs/namespace-taxonomy.md`](../lab-home-gitops/docs/namespace-taxonomy.md).

## Ownership

| Concern | Path |
| ------- | ---- |
| All VMs + LXC (Terraform) | `terraform/` |
| Guest + k8s Ansible | `ansible/` |
| Cilium + Argo CD bootstrap | `scripts/` |
| Platform apps (GitOps) | [`lab-home-gitops`](https://github.com/nasraldin/lab-home-gitops) |
| CI templates | [`pipeline-templates`](https://github.com/nasraldin/pipeline-templates) |

## Documentation

| Topic | Link |
| ----- | ---- |
| Inventory + cutover status | [lab-home-inventory](../docs/operations/lab-home-inventory.md) |
| Restructure sequence | [lab-restructure-2026-07-30](../docs/operations/lab-restructure-2026-07-30.md) |
| E2E reset checklist | [docs/runbook/e2e-reset-checklist.md](docs/runbook/e2e-reset-checklist.md) |
| Bring-up issues | [docs/runbook/bring-up-issues-2026-07.md](docs/runbook/bring-up-issues-2026-07.md) |
| Daily use / public URLs | [dev-homelab docs](https://nasraldin.github.io/dev-homelab/) |
