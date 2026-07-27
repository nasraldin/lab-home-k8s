# Bring-up issues & fixes (2026-07 factory reset)

Record of failures hit during the home-lab factory reset and the code/runbook
fixes applied so the next `terraform apply` → `make bring-up` path does not
hang or fail the same way.

## Canonical IP map (do not regress)

| Guest | IP |
|-------|-----|
| `pve01` | `192.168.68.13` (**fixed**; never change on reset) |
| `infra-01` | `.14` |
| `gitlab-01` | `.15` |
| `runner-01` | `.16` |
| `k8s-cp-01` | `.17` |
| `k8s-w-01..03` | `.18–.20` |
| `docker-01` | `.21` |
| `dockhand` / `portainer` / `ai-01` | `.22` / `.23` / `.24` |
| Cilium LB | `.100–.119` |

## Issues and fixes

### 1. Infisical could not boot (Postgres / PgCat missing)

- **Symptom:** `/api/status` connection reset; logs `KnexTimeoutError` / boot migration failed.
- **Cause:** Compose expected PgCat on `database-01:6432`; home lab has no `database-01`.
- **Fix:** Local `postgres:16-alpine` service in Infisical compose; `DB_CONNECTION_URI` → `db:5432`. Ensure `proxy` Docker network exists. Retries on `pull`/`up`. Longer API wait.

### 2. Docker Hub / registry pull timeouts

- **Symptom:** `redis:7-alpine` or NPM image pull timed out mid-`compose up`.
- **Fix:** Explicit `docker compose pull` + `up` with `retries: 5`, `delay: 15` for Infisical, NPM, it-tools, mailpit.

### 3. AIStor license missing on control node

- **Symptom:** Ansible assert failed for `files/aistor/minio.license`.
- **Fix:** Document copy path in `ansible/files/aistor/README.md` (license stays gitignored). Copy from `ansible-lab` or MinIO download before `make ansible`.

### 4. GitLab Runner register failed (UFW)

- **Symptom:** `gitlab-runner register` failed; runner could not reach `:80` on GitLab.
- **Cause:** `guest_common` UFW default deny; only SSH allowed on `gitlab-01`.
- **Fix:** `inventory/host_vars/gitlab-01.yml` allows LAN `80/443/5050`. Same pattern for `infra-01` and `docker-01`.

### 5. AdGuard vs Technitium on `:53`

- **Symptom:** AdGuard configure HTTP 400 / bind failures.
- **Fix:** Technitium authoritative on `127.0.0.1:5300`; AdGuard owns LAN `:53` with upstream `[/lab/]127.0.0.1:5300`. Cookie-based AdGuard login handling (not JSON token).

### 6. Kubernetes Ready wait hung Ansible (~10 min)

- **Symptom:** `Wait until all workers are Ready` failed after joins; CoreDNS Pending.
- **Cause:** Nodes stay `NotReady` until Cilium; Ansible ran before `make bootstrap`.
- **Fix:** Wait only until worker **nodes are registered**, then label. `make bootstrap` installs Cilium (Ready) then Argo. Makefile `bring-up` target encodes order. Cilium defaults `K8S_API_HOST=192.168.68.17`.

### 7. `/etc/kubernetes` missing during k8s_common

- **Symptom:** Copy `pod-resolv.conf` failed — destination directory missing.
- **Fix:** Create `/etc/kubernetes` before copy; only patch kubelet `resolvConf` when config file exists.

### 8. Argo CD could not sync GitOps

- **Symptom:** `ComparisonError` / HTTP 530 to `https://gitlab.nasraldin.com/...`.
- **Cause:** Fresh GitLab had no projects; public Tunnel not healthy; install script fell back to GitHub `gh` token.
- **Fix:**
  - Prefer LAN repo URL: `http://192.168.68.15/homelab/lab-home-gitops.git`
  - Require `GITOPS_TOKEN` (GitLab PAT); do not use `gh`
  - `scripts/seed-gitlab-gitops.sh` creates group/project and pushes `lab-home-gitops`
  - Root Application template uses `REPO_URL_PLACEHOLDER`

### 9. GPU / Ollama (AI)

- PCI mapping needed `subsystem-id`; VFIO bind; Ollama + `gemma4:12b` on `ai-01`.
- Guest may still run CPU inference until ROCm/`amdgpu` in guest is finished (device visible; driver optional follow-up).

## Recommended clean reset path

```bash
# After Proxmox host is up at .13 and terraform credentials exist:
cd lab-home-k8s/terraform && terraform apply
# Place AIStor license: ansible/files/aistor/minio.license
cd .. && make ansible   # or: make bring-up after token ready

# Mint GitLab PAT (api + write_repository), then:
GITLAB_TOKEN=glpat-... ./scripts/seed-gitlab-gitops.sh
GITOPS_TOKEN=glpat-... make bootstrap
make verify
```

## Verification snapshot (post-fix)

- `kubectl get nodes` → 4 Ready
- `./scripts/verify.sh` → OK
- Infisical / NPM / Ollama / GitLab sign-in / runner verify → healthy on LAN
- Argo `root` Application reaches GitOps over LAN URL
