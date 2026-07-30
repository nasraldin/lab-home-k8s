# End-to-end factory reset checklist (pve01)

Use this after a full wipe/rebuild of guests on **pve01 (`192.168.68.13`)**.
Goal: Terraform + Ansible + GitOps bring every core service up **without ad-hoc debugging**.

Canonical inventory: [lab-home-inventory.md](../../../docs/operations/lab-home-inventory.md).
Restructure: [lab-restructure-2026-07-30.md](../../../docs/operations/lab-restructure-2026-07-30.md).
Do **not** move pve01 off `.13`.

| Guest | IP |
| ----- | -- |
| pve01 | `.13` |
| dns-01 (Technitium) | `.11` |
| ssh-01 (jumpbox) | `.12` |
| adguard-01 (DNS for LAN/Mac) | `.14` |
| gitlab-01 | `.15` |
| runner-01 | `.16` |
| k8s-cp-01 (**6 GiB**) | `.17` |
| k8s-w-01..03 | `.18–.20` |
| docker-01 | `.21` |
| infisical-01 | `.25` |
| llm-01 | `.26` |
| Cilium LB pool | `.100–.119` |

**Destroyed (do not recreate):** VM 110 fat infra, LXC 118/119 Dockhand/Portainer, VM 120 `ai-01`, old **infra-01** (apps moved; jumpbox is **ssh-01** `.12`).

See also: [bring-up-issues-2026-07.md](./bring-up-issues-2026-07.md) · `CREDENTIALS.md` (gitignored pointer map)

---

## 0) Preconditions (laptop + Proxmox)

- [ ] Mac can SSH to `root@192.168.68.13` and guests
- [ ] `lab-home-k8s/terraform/credentials.auto.tfvars` has a valid Proxmox API token
- [ ] `lab-home-k8s/ansible/secrets.yml` present
- [ ] AIStor license at `ansible/files/aistor/minio.license`
- [ ] Sibling checkout `../lab-home-gitops` exists
- [ ] Wi‑Fi DNS: AdGuard **`192.168.68.14`** (+ optional `1.1.1.1`) — after DNS playbook
- [ ] `/etc/resolver/lab` → `nameserver 192.168.68.14`
- [ ] During cutover: temporary public DNS is OK
- [ ] Cloudflare: export `CLOUDFLARE_API_TOKEN` when running tunnel bootstrap

---

## 1) Terraform — recreate guests

```bash
cd lab-home-k8s/terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

**llm-01 note:** GPU passthrough often needs `root@pam` via
`terraform/scripts/pct-create-restructure-lxcs.sh` then `terraform import`.

**Verify**

- [ ] Guests running (VMs + CTs for DNS / ssh-01 / Infisical / llm-01)
- [ ] `ping` `.11` `.12` `.14`–`.21` `.25` `.26`
- [ ] `pve01` still `.13` with default route via `.1`
- [ ] Mac `/etc/resolver/lab` → `.14` (`ansible-lab/scripts/mac-resolver-lab.sh`)

---

## 2) Ansible — OS + services

```bash
cd lab-home-k8s
# Documented order (not only `make ansible`):
# dns → restore Mac DNS to AdGuard .14 → infisical → docker-hosts → infra (ssh-01)
# → gitlab → k8s → ollama → openclaw (overlay build + k8s import)
make ansible
```

**What this must leave healthy**

| Host | Must be up |
| ---- | ---------- |
| adguard-01 | AdGuard `:53` / UI `:3000` (LAN/Mac DNS) |
| dns-01 | Technitium `:5380` (auth for `lab` / `dev.test`) |
| ssh-01 | Jumpbox / SSH bastion (no app ports) |
| gitlab-01 | HTTP `:80`, registry `:5050`, `external_url http://gitlab.lab` |
| runner-01 | Host runner registered (or ready for token) |
| k8s nodes | Registered (Ready after Cilium) |
| k8s workers | Longhorn disk mounted at `/var/lib/longhorn` |
| docker-01 | NPM `:80/:443/:81`, Stalwart, AIStor `:9000/:9001`, Dockhand `:3000`, Portainer `:9443`, it-tools, mailpit, OpenClaw compose |
| infisical-01 | Infisical `:8090` + local Postgres/Redis |
| llm-01 | Ollama `:11434` (GPU after host amdgpu prep) |

**Verify**

```bash
dig @192.168.68.14 gitlab.lab +short    # .15
curl -sI http://gitlab.lab/ | head
curl -s http://192.168.68.25:8090/api/status
curl -s http://192.168.68.26:11434/api/tags
ssh nasr@192.168.68.18 'findmnt /var/lib/longhorn && df -h /var/lib/longhorn'
```

- [ ] `*.lab` resolves via AdGuard `.14` → Technitium `.11`
- [ ] Each worker: Longhorn data disk mounted (not OS root)

---

## 3) Seed GitOps repo on LAN GitLab

```bash
export GITLAB_TOKEN=glpat-...   # mint temporary PAT; revoke after seed+bootstrap
export GITOPS_TOKEN="$GITLAB_TOKEN"
cd lab-home-k8s
make seed-gitops
```

- [ ] http://192.168.68.15/homelab/lab-home-gitops exists
- [ ] **Revoke** temporary bring-up PAT(s) on gitlab-01 (`gitlab-rails` / UI)

---

## 4) Bootstrap cluster (Cilium + Argo + day-0 secrets)

```bash
cd lab-home-k8s
make bootstrap
make wait-longhorn
make verify
```

Namespaces after sync: `ai-tools`, `observability`, `database`, `artifacts`,
`storage`, `security`, `gitops`, `apps`, `argocd` — see
[`lab-home-gitops/docs/namespace-taxonomy.md`](../../../lab-home-gitops/docs/namespace-taxonomy.md).

```bash
kubectl get nodes
kubectl -n argocd get app root
kubectl -n ai-tools get pods
kubectl -n gitops get pods
./scripts/verify.sh
```

---

## 5) GitOps sync waves

| Wave | What | Namespace |
| ---- | ---- | --------- |
| 0 | Canonical namespaces | — |
| 10–25 | cert-manager, ESO, Infisical op, Kyverno, KEDA | `security` / `gitops` |
| 30 | Longhorn | `storage` |
| 40 | CNPG + DB operators (incl. MariaDB **CRDs** chart) | `database` |
| 42–46 | Keycloak, Sonar (interim) | `apps` |
| | Harbor, Verdaccio | `artifacts` |
| 50+ | Observability | `observability` |
| | GitLab Runner + KEDA ScaledObject | `gitops` |
| | LiteLLM, LibreChat, n8n, OpenClaw | `ai-tools` |

**Cilium LB IPs (must stay unique)**

| IP | Owner |
| -- | ----- |
| `.100` | Argo CD |
| `.101` | Harbor |
| `.102` | Grafana |
| `.103` | Keycloak |
| `.104` | Longhorn UI |
| `.105` | LibreChat |
| `.106` | Verdaccio (`npm.lab`) |
| `.107` | n8n |
| `.108` | LiteLLM |
| `.110` | OTel collector |
| `.112` | Sonar |
| `.113` | OpenClaw |

---

## 6) Cloudflare Tunnel

Origins: GitLab `.15`, Proxy `.21:81`, Dockhand/Minio/Portainer → **`.21`**,
Infisical → **`.25`**, Verdaccio `.106`, …

---

## 7) Infisical machine identity (day-2)

Bootstrap a fresh Infisical instance (no users yet):

```bash
# Creates admin user + org + Instance Admin Identity token
curl -X POST http://192.168.68.25:8090/api/v1/admin/bootstrap \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@lab.nasraldin.com","password":"<strong>","organization":"Homelab"}'
```

Then attach Universal Auth + create a client secret (store in `secrets.yml` only):

1. `POST /api/v1/auth/universal-auth/identities/{identityId}` → `clientId`
2. `POST /api/v1/auth/universal-auth/identities/{identityId}/client-secrets` → `clientSecret`
3. Put `vault_infisical_ua_client_id` / `vault_infisical_ua_client_secret` (and admin email/password, org/identity ids) in `ansible/secrets.yml`
4. `kubectl -n security create secret generic infisical-universal-auth --from-literal=clientId=… --from-literal=clientSecret=…`
5. Seed: `ansible-playbook playbooks/infisical-seed.yml -e @secrets.yml`
6. `InfisicalSecret` `hostAPI`: **`http://192.168.68.25:8090/api`** (not `.14` / old infra); credentialsRef namespace **`security`**

Until universal-auth exists, day-0 `apply-bootstrap-secrets.sh` keeps apps up.

---

## 8) OpenClaw

- Overlay image `ghcr.io/openclaw/openclaw:2026.7.1-2-slim` is **lab-built** (not on public GHCR).
- `ansible-playbook playbooks/openclaw.yml -e @secrets.yml` builds on docker-01, seeds `data/openclaw.json` (`gateway.mode=local`), and imports the tarball onto k8s nodes.
- NPM `openclaw.lab` → Cilium LB `.113` (primary); docker-01 `:18789` is parallel/fallback.
- Accept: `curl -sSI http://openclaw.lab/` → 302 `/__oc_boot`; with `oc_boot=1` → 200; WS upgrade works.

---

## 9) Acceptance (LAN)

- [ ] `http://gitlab.lab` HTTP sign-in
- [ ] `http://argo.lab` · `http://proxy.lab:81` · `http://minio.lab:9001`
- [ ] `http://infisical.lab` or `:8090` on `.25` (seeded + UA secret)
- [ ] `http://webmail.lab` / `http://inbox.lab` (Bulwark; same-origin JMAP)
- [ ] `http://openclaw.lab` → 302 `/__oc_boot` → Control UI
- [ ] `http://ollama.lab:11434/api/tags` → `.26`
- [ ] `kubectl -n database get cluster` · `kubectl -n ai-tools get pods`
- [ ] GitLab runner in `gitops` online (or host runner on `.16`)

## 10) If something is wrong

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| InfisicalSecret failures | Wrong `hostAPI` or no universal-auth | `.25`; bootstrap + UA secret |
| MariaDB operator stuck | Missing CRDs chart | `platform/data` `mariadb-operator-crds` |
| LibreChat PVC/update issues | RollingUpdate on single PVC | Deployment `strategy: Recreate` |
| Kyverno ImagePullBackOff cleanup Job | bitnami/kubectl gone | `policyReportsCleanup.enabled: false` + `registry.k8s.io/kubectl` |
| Runner cannot reach GitLab | Public URL / DNS | LAN IP + `hostAliases` — [gitlab-runner-k8s.md](../../../docs/operations/gitlab-runner-k8s.md) |
| Ollama 100% CPU | VFIO still bound / no IGPU env | [ollama-llm-01.md](../../../docs/operations/ollama-llm-01.md) |
| OpenClaw exit 78 / crash-loop | Missing `gateway.mode=local` | Seed `openclaw.json` via openclaw role |
| OpenClaw ImagePullBackOff | Lab overlay not imported | Re-run `playbooks/openclaw.yml` import |
| Hosts unreachable | pve01 outage | Recover PVE; cutover is staged — do not invent live status |

Update `CREDENTIALS.md` after a successful bring-up if passwords rotated.
