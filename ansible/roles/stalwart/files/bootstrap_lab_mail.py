#!/usr/bin/env python3
"""Idempotent Stalwart bootstrap + seed mailbox for lab local mail.

Stalwart rejects non-reserved fake TLDs like .lab — use .test (RFC 6761).
Runs from Ansible after compose up; no interactive wizard.
"""
from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


def env(name: str, default: str | None = None) -> str:
    val = os.environ.get(name, default)
    if val is None or val == "":
        raise SystemExit(f"missing env {name}")
    return val


def basic(user: str, password: str) -> str:
    return "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()


def http_json(method: str, url: str, auth: str, body: dict | None = None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Authorization": auth,
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method=method,
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        raw = resp.read().decode() or "null"
        return json.loads(raw)


def jmap(url: str, auth: str, calls: list):
    return http_json(
        "POST",
        url,
        auth,
        {
            "using": ["urn:ietf:params:jmap:core", "urn:stalwart:jmap"],
            "methodCalls": calls,
        },
    )


def wait_auth(session_url: str, auth: str, attempts: int = 45) -> None:
    last: Exception | None = None
    for _ in range(attempts):
        try:
            http_json("GET", session_url, auth)
            return
        except Exception as exc:  # noqa: BLE001
            last = exc
            time.sleep(2)
    raise SystemExit(f"auth not ready at {session_url}: {last}")


def compose_restart(compose_dir: str) -> None:
    subprocess.check_call(
        ["docker", "compose", "-f", f"{compose_dir}/compose.yaml", "restart"],
        cwd=compose_dir,
    )
    time.sleep(6)


def write_creds(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2) + "\n")
    path.chmod(0o600)


def account_ids_by_name(jmap_url: str, auth: str, name: str) -> list[str]:
    out = jmap(jmap_url, auth, [["x:Account/query", {"filter": {"name": name}}, "c1"]])
    return out["methodResponses"][0][1].get("ids") or []


def set_password(jmap_url: str, auth: str, account_id: str, password: str) -> None:
    out = jmap(
        jmap_url,
        auth,
        [
            [
                "x:Account/set",
                {
                    "update": {
                        account_id: {
                            "credentials": {
                                "0": {"@type": "Password", "secret": password}
                            }
                        }
                    }
                },
                "c1",
            ]
        ],
    )
    updated = out["methodResponses"][0][1].get("updated") or {}
    if account_id not in updated:
        raise SystemExit(f"password update failed: {out}")


def main() -> int:
    jmap_url = env("STALWART_JMAP_URL", "http://127.0.0.1:8080/jmap/")
    jmap_base = jmap_url.rstrip("/")
    session_url = (
        jmap_base + "/session"
        if jmap_base.endswith("/jmap")
        else "http://127.0.0.1:8080/jmap/session"
    )

    recovery_user = env("STALWART_RECOVERY_USER", "admin")
    recovery_password = env("STALWART_RECOVERY_PASSWORD")
    hostname = env("STALWART_HOSTNAME", "mail.dev.test")
    domain = env("STALWART_DOMAIN", "dev.test")
    admin_email = env("STALWART_ADMIN_EMAIL", f"admin@{domain}")
    admin_password = env("STALWART_ADMIN_PASSWORD")
    mailbox_password = env("STALWART_MAILBOX_PASSWORD")
    seed_raw = os.environ.get(
        "STALWART_SEED_MAILBOXES",
        '["admin","info","noreply","support","notify"]',
    )
    try:
        seed_mailboxes = json.loads(seed_raw)
    except json.JSONDecodeError:
        seed_mailboxes = [p.strip() for p in seed_raw.split(",") if p.strip()]
    if not isinstance(seed_mailboxes, list) or not seed_mailboxes:
        raise SystemExit("STALWART_SEED_MAILBOXES must be a non-empty JSON list")
    compose_dir = env("STALWART_COMPOSE_DIR", "/opt/stalwart")
    creds_file = Path(env("STALWART_CREDS_FILE", f"{compose_dir}/bootstrap-admin.json"))

    recovery_auth = basic(recovery_user, recovery_password)
    in_bootstrap = False
    try:
        wait_auth(session_url, recovery_auth, attempts=20)
        out = jmap(jmap_url, recovery_auth, [["x:Bootstrap/get", {"ids": ["singleton"]}, "c1"]])
        if out["methodResponses"][0][1].get("list"):
            in_bootstrap = True
    except Exception:
        in_bootstrap = False

    generated_admin_secret: str | None = None

    if in_bootstrap:
        out = jmap(
            jmap_url,
            recovery_auth,
            [
                [
                    "x:Bootstrap/set",
                    {
                        "update": {
                            "singleton": {
                                "serverHostname": hostname,
                                "defaultDomain": domain,
                                "requestTlsCertificate": False,
                                "generateDkimKeys": True,
                                "directory": {"@type": "Internal"},
                                "dnsServer": {"@type": "Manual"},
                                "tracer": {
                                    "@type": "Log",
                                    "path": "/var/lib/stalwart/logs",
                                    "prefix": "stalwart",
                                    "rotate": "daily",
                                    "ansi": False,
                                    "multiline": False,
                                    "enable": True,
                                    "level": "info",
                                    "lossy": False,
                                    "events": {},
                                    "eventsPolicy": "exclude",
                                },
                            }
                        }
                    },
                    "c1",
                ]
            ],
        )
        updated = out["methodResponses"][0][1].get("updated", {}).get("singleton")
        if not updated:
            raise SystemExit(f"bootstrap failed: {out}")
        generated_admin_secret = updated["secret"]
        print(f"bootstrapped domain={domain} admin={updated['username']}")
        compose_restart(compose_dir)

    # Authenticate as admin (generated secret first, then vault password)
    auth_candidates: list[tuple[str, str]] = []
    if generated_admin_secret:
        auth_candidates.append((admin_email, generated_admin_secret))
    auth_candidates.append((admin_email, admin_password))
    if creds_file.exists():
        saved = json.loads(creds_file.read_text())
        auth_candidates.append(
            (saved.get("admin_email", admin_email), saved.get("admin_password", admin_password))
        )
    # Recovery may still work briefly
    auth_candidates.append((recovery_user, recovery_password))

    admin_auth = None
    last_err: Exception | None = None
    for user, password in auth_candidates:
        try:
            wait_auth(session_url, basic(user, password), attempts=15)
            # Confirm JMAP works (not just recovery HTML)
            try:
                jmap(jmap_url, basic(user, password), [["x:Domain/query", {}, "c1"]])
            except Exception:
                continue
            admin_auth = basic(user, password)
            current_user, current_pass = user, password
            break
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            continue
    if admin_auth is None:
        raise SystemExit(f"could not authenticate as admin: {last_err}")

    # Pin admin password to vault value
    if current_user != admin_email or current_pass != admin_password:
        ids = account_ids_by_name(jmap_url, admin_auth, "admin")
        if not ids:
            raise SystemExit("admin account id not found")
        set_password(jmap_url, admin_auth, ids[0], admin_password)
        admin_auth = basic(admin_email, admin_password)
        wait_auth(session_url, admin_auth, attempts=15)
        print("admin password updated")
    else:
        print(f"already configured; using admin={admin_email}")

    write_creds(
        creds_file,
        {
            "hostname": hostname,
            "domain": domain,
            "admin_email": admin_email,
            "admin_password": admin_password,
            "mailboxes": [f"{local}@{domain}" for local in seed_mailboxes],
            "mailbox_password_note": "non-admin seeds use vault_stalwart_mailbox_password",
            "ui": "http://mail.lab/admin",
            "webmail": "http://webmail.lab",
            "jmap": "http://webmail.lab/jmap/",
        },
    )

    out = jmap(jmap_url, admin_auth, [["x:Domain/query", {}, "c1"]])
    domain_ids = out["methodResponses"][0][1].get("ids") or []
    if not domain_ids:
        raise SystemExit("no domain id after bootstrap")
    domain_id = domain_ids[0]

    for mailbox_local in seed_mailboxes:
        local = str(mailbox_local).strip().lower()
        if not local:
            continue
        # admin@ is the bootstrap admin account — password already pinned above
        if local == "admin":
            print(f"mailbox exists {local}@{domain}")
            continue
        password = mailbox_password
        existing = account_ids_by_name(jmap_url, admin_auth, local)
        if existing:
            set_password(jmap_url, admin_auth, existing[0], password)
            print(f"mailbox exists {local}@{domain}")
            continue

        out = jmap(
            jmap_url,
            admin_auth,
            [
                [
                    "x:Account/set",
                    {
                        "create": {
                            "mailbox": {
                                "@type": "User",
                                "name": local,
                                "domainId": domain_id,
                                "credentials": {
                                    "0": {"@type": "Password", "secret": password}
                                },
                                "memberGroupIds": {},
                                "roles": {"@type": "User"},
                                "permissions": {"@type": "Inherit"},
                                "quotas": {},
                                "aliases": {},
                                "encryptionAtRest": {"@type": "Disabled"},
                            }
                        }
                    },
                    "c1",
                ]
            ],
        )
        created = out["methodResponses"][0][1].get("created")
        if not created:
            raise SystemExit(f"mailbox create failed for {local}: {out}")
        print(f"created mailbox {local}@{domain}")

    # Bulwark (webmail.lab) talks to JMAP in the browser → needs CORS on mail.lab.
    # https://stalw.art/docs/http/security/
    out = jmap(
        jmap_url,
        admin_auth,
        [
            [
                "x:Http/set",
                {"update": {"singleton": {"usePermissiveCors": True}}},
                "c1",
            ]
        ],
    )
    updated = out["methodResponses"][0][1].get("updated")
    if updated is None and out["methodResponses"][0][0] == "error":
        raise SystemExit(f"enable CORS failed: {out}")
    print("http usePermissiveCors=true (for Bulwark on webmail.lab)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except urllib.error.HTTPError as exc:
        sys.stderr.write(exc.read().decode(errors="replace") + "\n")
        raise
