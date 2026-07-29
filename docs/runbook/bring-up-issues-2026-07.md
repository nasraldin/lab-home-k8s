# Bring-up issues & fixes (2026-07 factory reset)

Record of failures hit during the home-lab factory reset and the code/runbook
fixes applied so the next `terraform apply` → `make bring-up` path does not
hang or fail the same way.

**Topology updates (2026-07-30):** DNS → `adguard-01`/`.10` + `dns-01`/`.11`;
Infisical → `infisical-01`/`.25`; Docker apps → `docker-01`/`.21`; Ollama →
`llm-01`/`.26`. See [lab-restructure-2026-07-30](../../../docs/operations/lab-restructure-2026-07-30.md).
Historical issue text may still mention “Infisical on infra-01” — treat those as
pre-restructure unless noted.

## Canonical IP map (do not regress)

| Guest | IP |
| ----- | -- |
| `pve01` | `192.168.68.13` (**fixed**) |
| `adguard-01` / `dns-01` | `.10` / `.11` |
| `infra-01` | `.14` (jumpbox after drain) |
| `gitlab-01` | `.15` |
| `runner-01` | `.16` |
| `k8s-cp-01` | `.17` |
| `k8s-w-01..03` | `.18–.20` |
| `docker-01` | `.21` |
| dockhand / portainer LXCs (legacy) | `.22` / `.23` |
| `ai-01` (standby) | `.24` |
| `infisical-01` | `.25` |
| `llm-01` | `.26` |
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

### 8. `*.lab` URLs “can’t be reached” in the browser

- **Symptom:** `http://gitlab.lab` fails in Safari/Chrome while `curl`/IP works.
- **Causes:**
  1. Mac DNS was `1.1.1.1` (not AdGuard `.14`).
  2. GitLab `external_url` was `https://…` so `/` redirected to **`https://gitlab.lab`** (no LAN TLS) and sent HSTS + Secure cookies.
  3. Wrong Omnibus keys (`gitlab_rails['nginx'][…]` ignored); need top-level `nginx['listen_https']=false` + `nginx['hsts_max_age']=0`.
- **Fix:** `gitlab_external_url: http://gitlab.lab`; correct `nginx[]` / `registry_nginx[]` keys; AdGuard DNS + optional `/etc/resolver/lab`. Clear browser HSTS for `gitlab.lab` if previously visited.

### 9. Argo CD could not sync GitOps

- **Symptom:** `ComparisonError` / HTTP 530 to `https://gitlab.nasraldin.com/...`.
- **Cause:** Fresh GitLab had no projects; public Tunnel not healthy; install script fell back to GitHub `gh` token.
- **Fix:**
  - Prefer LAN repo URL: `http://192.168.68.15/homelab/lab-home-gitops.git`
  - Require `GITOPS_TOKEN` (GitLab PAT); do not use `gh`
  - `scripts/seed-gitlab-gitops.sh` creates group/project and pushes `lab-home-gitops`
  - Root Application template uses `REPO_URL_PLACEHOLDER`

### 10. GPU / Ollama (AI)

- **Current path:** privileged LXC `llm-01` with host `amdgpu` device passthrough
  — [ollama-llm-01.md](../../../docs/operations/ollama-llm-01.md).
- **Standby:** `ai-01` VFIO VM kept until `ollama ps` shows GPU on llm-01.
- Historical: PCI mapping needed `subsystem-id`; VFIO bind on `ai-01`.

### 11. Browser forces `https://gitlab.lab` while `/users/sign_in` works

- **Server side:** `external_url 'http://gitlab.lab'` and `/` → `Location: http://gitlab.lab/users/sign_in` (no HSTS).
- **Client side:** Chrome/Safari HTTPS-First or **cached HSTS** from the earlier `https://` Omnibus config.
- **Fix:** Clear HSTS for `gitlab.lab` (Chrome: `chrome://net-internals/#hsts` → Delete), or use a private window. Prefer typed `http://gitlab.lab`.

### 12. Public URLs: Cloudflare 1014 + tunnel down

- **1014 CNAME Cross-User Banned:** zone had proxied wildcard `*.nasraldin.com` → `77980.bodis.com` (other CF customer). Names without an explicit tunnel CNAME (`argo`, `npm`, `grafana`, …) hit that wildcard.
- **Fix:** Delete the Bodis wildcard; create CNAMEs → `9970638a-….cfargotunnel.com`; extend tunnel ingress (Argo `.100`, NPM `.21:81`, GitLab `.15`, Dockhand `.22`, …).
- **Tunnel down / 530:** after reset, `pve01` had **no default route** in the kernel despite `gateway` in `/etc/network/interfaces`. `cloudflared` could not reach Cloudflare (`network is unreachable`).
- **Fix:** `ip route replace default via 192.168.68.1 dev vmbr0` + `post-up` line on `vmbr0`. Stale tunnel origins (GitLab → `.14`) updated to `.15`.
- **Grafana/Harbor public 530:** expected until Cilium LBs `.101`/`.102` exist (GitOps apps still syncing). Use `*.lab` / IPs on LAN.

### 13. `npm.lab` / `npm.nasraldin.com` opened Nginx Proxy Manager

- **Cause:** In this repo “NPM” meant **Nginx Proxy Manager** (`docker-01:81`), so DNS/tunnel pointed `npm.*` there.
- **Expected:** **Verdaccio** (npm registry).
- **Fix:** Verdaccio on Cilium LB `192.168.68.106:80`; `npm.lab` / `npm.nasraldin.com` → Verdaccio; Proxy Manager moved to `proxy.lab:81` / `proxy.nasraldin.com`.

### 14. Argo apps OutOfSync / CrashLoop after clean reset

- **Causes:**
  1. InfisicalSecret `hostAPI` pointed at wrong IP (must track Infisical host —
     now **`infisical-01` `.25`**, was infra-01 `.14` / mistaken `.10`).
  2. AnythingLLM and Verdaccio both claimed LB `.106`; Harbor blocked when AnythingLLM took `.101`.
  3. CNPG operator CrashLoop — CRDs not created (`Pooler` missing) + Kyverno requiring resource requests.
  4. No CNPG `Cluster` — Keycloak/Sonar expected Postgres Service that never existed.
  5. Platform secrets assumed Infisical machine identity that is never created in bring-up.
  6. `make bring-up` skipped GitOps seed + day-0 secrets + Longhorn wait.
- **Fixes:**
  - Correct `hostAPI` → Infisical LAN (`http://192.168.68.25:8090/api` post-restructure); LB map unique.
  - CNPG Helm `crds.create: true` + MariaDB **operator CRDs** chart; resource requests; postgres Cluster.
  - LibreChat Mongo Deployment `strategy: Recreate` (PVC).
  - Kyverno: `policyReportsCleanup.enabled: false`; cleanup images from `registry.k8s.io/kubectl`.
  - GitLab runner: token Secret, URL via `.15` + `hostAliases`, KEDA `minReplicaCount: 1`.
  - `scripts/apply-bootstrap-secrets.sh` + `wait-longhorn.sh`; checklist updated.

### 15. Longhorn PVCs faulted / `insufficient storage` (data disk never mounted)

- **Symptom:** Volumes `detached/faulted`, `ReplicaSchedulingFailure`, apps stuck Pending; OS root (`~60Gi`) fills while Terraform `data_disk_gb=100` disks sit unused.
- **Cause:** Terraform attaches a second disk for Longhorn, but **nothing formatted/mounted it** before Longhorn installed.
- **Fix (in tree):** Ansible role `k8s_longhorn_disk`; right-size PVCs; `scripts/wait-longhorn.sh` checks disk capacity.

### 16. Kyverno PolicyViolation warnings (require-resource-requests, hostNetwork)

- **Symptom:** Many `PolicyViolation` Warning events on observability, harbor, verdaccio, cert-manager Deployments/StatefulSets.
- **Cause:** Helm charts ship without `resources.requests`; Kyverno autogen rules audit controllers. node-exporter needs `hostNetwork`.
- **Fix (in tree):** Add `resources.requests` in GitOps Helm values; exclude `observability` from `disallow-host-namespaces` only; RabbitMQ → `bitnamilegacy/*` images.

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
- Infisical (`.25`) / NPM (docker-01) / Ollama (`llm-01`) / GitLab / runner → healthy on LAN
- Argo `root` Application reaches GitOps over LAN URL
- Namespaces match taxonomy (`ai-tools`, `gitops`, …) — unused per-app NS pruned when empty
