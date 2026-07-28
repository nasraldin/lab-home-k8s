# End-to-end factory reset checklist (pve01)

Use this after a full wipe/rebuild of guests on **pve01 (`192.168.68.13`)**.  
Goal: Terraform + Ansible + GitOps bring every core service up **without ad-hoc debugging**.

Canonical IP map is fixed — **do not move pve01 off `.13`**; guests start at `.14+`.

| Guest                        | IP                    |
| ---------------------------- | --------------------- |
| pve01                        | `.13`                 |
| infra-01                     | `.14`                 |
| gitlab-01                    | `.15`                 |
| runner-01                    | `.16`                 |
| k8s-cp-01                    | `.17`                 |
| k8s-w-01..03                 | `.18–.20`             |
| docker-01                    | `.21`                 |
| dockhand / portainer / ai-01 | `.22` / `.23` / `.24` |
| Cilium LB pool               | `.100–.119`           |

See also: [bring-up-issues-2026-07.md](./bring-up-issues-2026-07.md) · `CREDENTIALS.md` (gitignored)

---

## 0) Preconditions (laptop + Proxmox)

- [ ] Mac can SSH to `root@192.168.68.13` and `nasr@192.168.68.14+`
- [ ] `lab-home-k8s/terraform/credentials.auto.tfvars` has a valid Proxmox API token
- [ ] `lab-home-k8s/ansible/secrets.yml` present (copy from `secrets.example.yml` + fill)
- [ ] AIStor license at `ansible/files/aistor/minio.license` (gitignored)
- [ ] Sibling checkout `../lab-home-gitops` exists (seed script pushes it to LAN GitLab)
- [ ] Wi‑Fi DNS includes AdGuard: `192.168.68.14` (+ optional `1.1.1.1`)
- [ ] Optional: `/etc/resolver/lab` → `nameserver 192.168.68.14`
- [ ] Cloudflare: export `CLOUDFLARE_API_TOKEN` when you run tunnel bootstrap (never store in git)

---

## 1) Terraform — recreate guests

```bash
cd lab-home-k8s/terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

**Verify**

- [ ] All guests running in Proxmox UI
- [ ] `ping 192.168.68.14` … `.24` succeed
- [ ] `pve01` still `192.168.68.13` with default route via `192.168.68.1`

```bash
ssh root@192.168.68.13 'ip -4 route | grep default'
# If missing: ip route replace default via 192.168.68.1 dev vmbr0
# (interfaces has post-up for this — confirm after reboot)
```

---

## 2) Ansible — OS + services

```bash
cd lab-home-k8s
make ansible
# equivalent: cd ansible && ansible-playbook -i inventory/hosts.yml playbooks/site.yml -e @secrets.yml
```

**What this must leave healthy**

| Host        | Must be up                                                                                             |
| ----------- | ------------------------------------------------------------------------------------------------------ |
| infra-01    | AdGuard `:3000`, Technitium `:5380` (DNS on `127.0.0.1:5300`), Infisical `:8090`, AIStor `:9000/:9001` |
| gitlab-01   | HTTP `:80`, registry `:5050`, `external_url http://gitlab.lab`                                         |
| runner-01   | Runner registered (or ready for token)                                                                 |
| k8s nodes   | kubelet up, nodes **Registered** (Ready comes after Cilium)                                            |
| k8s workers | Terraform `data_disk_gb` **mounted at `/var/lib/longhorn`** (role `k8s_longhorn_disk`)                 |
| docker-01   | Proxy Manager `:81`, it-tools `:1000`, Mailpit `:8025`                                                 |
| ai-01       | Ollama `:11434`                                                                                        |

**Verify**

```bash
dig @192.168.68.14 gitlab.lab +short    # .15
curl -sI http://gitlab.lab/ | head      # Location: http://gitlab.lab/users/sign_in
curl -s http://192.168.68.14:8090/api/status
curl -s http://192.168.68.24:11434/api/tags
# Longhorn data disk MUST be the 100G disk, not the 60G OS root:
ssh nasr@192.168.68.18 'findmnt /var/lib/longhorn && df -h /var/lib/longhorn'
# Expect ~98G size. If missing, Longhorn will fill the OS disk and PVCs fail.
```

- [ ] No HTTPS redirect on `gitlab.lab`
- [ ] `*.lab` resolves via AdGuard → Technitium
- [ ] Each worker: `findmnt /var/lib/longhorn` shows the data disk (~100G)

---

## 3) Seed GitOps repo on LAN GitLab

Fresh GitLab has **no** projects. Argo must use the **LAN** clone URL (public Tunnel may be down).

```bash
# Mint PAT in GitLab UI (api + write_repository + read_repository) or rails runner
export GITLAB_TOKEN=glpat-...
export GITOPS_TOKEN="$GITLAB_TOKEN"   # same PAT is fine for Argo repo Secret
cd lab-home-k8s
make seed-gitops
```

**Verify**

- [ ] http://192.168.68.15/homelab/lab-home-gitops exists
- [ ] `git ls-remote http://oauth2:${GITLAB_TOKEN}@192.168.68.15/homelab/lab-home-gitops.git` shows `main`

---

## 4) Bootstrap cluster (Cilium + Argo + day-0 secrets)

```bash
cd lab-home-k8s
# GITOPS_TOKEN must still be set
make bootstrap
# runs: fetch-kubeconfig → install-cilium → install-argocd → apply-bootstrap-secrets
```

**Sequence inside bootstrap (do not reorder)**

1. `fetch-kubeconfig.sh` — context `home-lab`
2. `install-cilium.sh` — nodes become Ready; LB pool `.100–.119`; Gateway API
3. `install-argocd.sh` — Argo on `.100`; registers GitOps repo with `GITOPS_TOKEN`; applies root Application with **LAN** `GITOPS_REPO`
4. `apply-bootstrap-secrets.sh` — creates Grafana/Harbor/Keycloak/Sonar/CNPG secrets from `secrets.yml` **before** Infisical identity exists

Then:

```bash
make wait-longhorn   # blocks until StorageClass longhorn is usable
make verify
```

**Verify**

```bash
kubectl get nodes                 # 4 Ready
kubectl get sc longhorn
kubectl -n argocd get app root
kubectl -n argocd get secret repo-lab-home-gitops
./scripts/verify.sh
```

- [ ] Core verify checks pass
- [ ] Argo UI: http://argo.lab (password from `argocd-initial-admin-secret`)
- [ ] Kyverno: no `PolicyViolation` warnings on platform apps:

```bash
kubectl get events -A --field-selector type=Warning \
  | rg -c 'PolicyViolation' || echo 0
# Expect 0 after GitOps sync (cert-manager, observability, harbor, verdaccio, rabbitmq)
```

---

## 5) GitOps sync waves (automatic — know the order)

| Wave  | What                                                                 | Depends on                                                                   |
| ----- | -------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| 10–25 | cert-manager, metrics-server, ESO, Infisical operator, Kyverno, KEDA | Cluster Ready                                                                |
| 30    | Longhorn                                                             | **Workers already have `/var/lib/longhorn` on the 100G data disk** (ansible) |
| 40    | Data operators (CNPG, Redis, RabbitMQ, MariaDB)                      | Longhorn CRDs / SSA                                                          |
| 41+   | CNPG `Cluster/postgres` + DB init Job                                | bootstrap secrets + Longhorn capacity                                        |
| 42–46 | Keycloak, Sonar, Harbor, Verdaccio                                   | Postgres + secrets                                                           |
| 50+   | Observability                                                        | grafana-admin secret                                                         |
| 55–63 | LiteLLM, LibreChat, AnythingLLM, n8n, Open WebUI                     | Longhorn PVCs + LiteLLM                                                      |

**Hard dependency:** Ansible `k8s_longhorn_disk` → Longhorn (wave 30) → CNPG Cluster → Keycloak/Sonar. Never start Longhorn on the OS root disk.

**Cilium LB IPs (must stay unique)**

| IP     | Owner                 |
| ------ | --------------------- |
| `.100` | Argo CD               |
| `.101` | Harbor                |
| `.102` | Grafana               |
| `.103` | Keycloak              |
| `.104` | Longhorn UI           |
| `.105` | LibreChat             |
| `.106` | Verdaccio (`npm.lab`) |
| `.107` | n8n                   |
| `.108` | LiteLLM               |
| `.109` | Open WebUI            |
| `.110` | OTel collector        |
| `.111` | AnythingLLM           |

Never assign two apps the same LB IP.

---

## 6) Cloudflare Tunnel (public URLs)

Only after LAN services answer:

```bash
cd cloudflare-tunnel
# config.env origins must match the IP map above (GitLab .15, Verdaccio .106, Proxy .21:81, …)
export CLOUDFLARE_API_TOKEN=...
./mac/bootstrap.sh --yes
```

- [ ] No proxied wildcard CNAME to Bodis/parking (causes Error **1014**)
- [ ] `https://gitlab.nasraldin.com` / `https://argo.nasraldin.com` / `https://npm.nasraldin.com` work
- [ ] Proxy Manager is `https://proxy.nasraldin.com` — **not** `npm.*`

---

## 7) Optional — Infisical machine identity (day-2)

Day-0 secrets already unblock apps. To switch SoT to Infisical:

1. Infisical UI → machine identity + Universal Auth
2. Seed projects: `ansible-playbook playbooks/infisical-seed.yml -e @secrets.yml`
3. Create Secret:

```bash
kubectl -n infisical-operator-system create secret generic infisical-universal-auth \
  --from-literal=clientId='...' \
  --from-literal=clientSecret='...'
```

4. Confirm `InfisicalSecret` CRs use `hostAPI: http://192.168.68.14:8090/api` (never `.10`)

---

## 8) One-liner full path (after TF apply + secrets + license)

```bash
cd lab-home-k8s
export GITLAB_TOKEN=glpat-...
export GITOPS_TOKEN="$GITLAB_TOKEN"
make bring-up
# = ansible → seed-gitops → bootstrap → wait-longhorn → verify
```

Then tunnel bootstrap (separate repo) when public URLs are needed.

---

## 9) Acceptance checklist (no debug expected)

### LAN

- [ ] `http://gitlab.lab` → sign-in (HTTP, not HTTPS)
- [ ] `http://argo.lab` → Argo UI
- [ ] `http://npm.lab` → Verdaccio (`/-/ping` → `{}`)
- [ ] `http://proxy.lab:81` → Nginx Proxy Manager
- [ ] `http://minio.lab:9001` → AIStor
- [ ] `http://adguard.lab:3000` / `http://dns.lab:5380`
- [ ] `http://ollama.lab:11434/api/tags` includes `gemma4:12b`
- [ ] `http://n8n.lab` / `http://librechat.lab:3080` when apps Healthy
- [ ] `kubectl get svc -A | grep LoadBalancer` — no duplicate EXTERNAL-IPs, Harbor on `.101`

### Cluster

- [ ] `kubectl -n argocd get applications` — no `ComparisonError`
- [ ] CNPG operator Running; `kubectl -n data get cluster` → postgres Healthy
- [ ] Longhorn UI `http://longhorn.lab`
- [ ] Grafana `http://grafana.lab` (admin from secrets)

### Public (if tunnel applied)

- [ ] GitLab / Argo / Verdaccio / Proxy / Homelab / MinIO HTTPS OK
- [ ] No Cloudflare 1014 / 530 on those hostnames

---

## 10) If something is wrong — look here first

| Symptom                              | Likely cause                               | Fix location                                                           |
| ------------------------------------ | ------------------------------------------ | ---------------------------------------------------------------------- |
| Argo `ComparisonError` / auth denied | Repo URL is public GitLab or bad PAT       | `install-argocd.sh` + `GITOPS_TOKEN`; child apps must use LAN repo URL |
| Harbor LB Pending                    | Another app stole `.101`                   | Check AnythingLLM / other `lbipam` annotations                         |
| Keycloak/Sonar CrashLoop             | No Postgres or missing secrets             | `apply-bootstrap-secrets.sh` + CNPG cluster                            |
| InfisicalSecret failures             | `hostAPI` still `.10` or no universal-auth | gitops `infisical-secret.yaml`; create auth Secret                     |
| CNPG CrashLoop `Pooler` CRD          | CRDs not installed                         | `platform/data/apps.yaml` `crds.create: true` + SSA                    |
| PVC Pending                          | Longhorn not Ready                         | `make wait-longhorn` before expecting apps                             |
| `gitlab.lab` forces HTTPS            | Browser HSTS / old Omnibus                 | Clear HSTS; `gitlab_external_url: http://gitlab.lab`                   |
| Public 1014                          | Wildcard CNAME to other CF customer        | Delete Bodis wildcard; explicit tunnel CNAMEs                          |
| Tunnel 530                           | pve01 no default route                     | Restore gateway `.1` on vmbr0                                          |
| `npm.*` shows Proxy Manager          | Wrong tunnel/DNS origin                    | Verdaccio `.106`; Proxy `proxy.*` → `.21:81`                           |

Update `CREDENTIALS.md` after a successful bring-up if passwords rotated.
