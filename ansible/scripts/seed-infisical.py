#!/usr/bin/env python3
"""Seed Infisical projects, folders, and secrets from ansible/secrets.yml.

Prerequisites
-------------
1. Infisical running (infra-01:8090) and an org + admin user exist (first-login UI).
2. A machine identity with Universal Auth, or email/password of an org admin.
3. secrets.yml filled from secrets.example.yml (never commit secrets.yml).

Auth (env — pick one):
  INFISICAL_UNIVERSAL_AUTH_CLIENT_ID + INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET
  OR INFISICAL_EMAIL + INFISICAL_PASSWORD

Other env:
  INFISICAL_URL          default http://192.168.68.25:8090
  INFISICAL_ORG_ID       optional; auto-picked if you belong to one org
  SECRETS_FILE           default ../../secrets.yml (relative to this script)
  SEED_MAP               default ../files/infisical/seed-map.yaml
  DRY_RUN=1              print actions only

Usage:
  export INFISICAL_UNIVERSAL_AUTH_CLIENT_ID=...
  export INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET=...
  python3 seed-infisical.py

  # or via Ansible
  ansible-playbook playbooks/infisical-seed.yml -e @secrets.yml
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:
    print("PyYAML required: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_SECRETS = SCRIPT_DIR.parent / "secrets.yml"
DEFAULT_MAP = SCRIPT_DIR.parent / "files" / "infisical" / "seed-map.yaml"


class InfisicalClient:
    def __init__(self, base_url: str, token: str) -> None:
        self.base = base_url.rstrip("/")
        self.token = token

    def _req(
        self,
        method: str,
        path: str,
        body: dict[str, Any] | None = None,
        query: dict[str, str] | None = None,
    ) -> Any:
        url = f"{self.base}{path}"
        if query:
            url += "?" + urllib.parse.urlencode(query)
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(
            url,
            data=data,
            method=method,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw = resp.read().decode()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            err = e.read().decode()
            raise RuntimeError(f"{method} {path} → {e.code}: {err}") from e

    def list_workspaces(self) -> list[dict[str, Any]]:
        # Prefer v2; fall back to v1 shapes.
        for path in ("/api/v2/workspace", "/api/v1/workspace"):
            try:
                data = self._req("GET", path)
                if isinstance(data, dict):
                    for key in ("workspaces", "projects"):
                        if key in data:
                            return list(data[key])
                if isinstance(data, list):
                    return data
            except RuntimeError:
                continue
        return []

    def create_workspace(self, name: str, slug: str, org_id: str) -> dict[str, Any]:
        # Infisical project create (API evolved; try common shapes).
        payloads = [
            {
                "projectName": name,
                "projectSlug": slug,
                "template": "default",
                "type": "secret-manager",
            },
            {"name": name, "slug": slug},
        ]
        last_err: Exception | None = None
        for body in payloads:
            if org_id:
                body = {**body, "organizationId": org_id}
            for path in (
                "/api/v2/workspace",
                "/api/v1/workspace",
                "/api/v1/projects",
            ):
                try:
                    return self._req("POST", path, body)
                except RuntimeError as e:
                    last_err = e
                    continue
        raise RuntimeError(f"create project {slug} failed: {last_err}")

    def ensure_folder(
        self, project_id: str, environment: str, path: str
    ) -> None:
        if path in ("", "/"):
            return
        # Create folder; ignore if exists.
        body = {
            "workspaceId": project_id,
            "environment": environment,
            "name": path.strip("/").split("/")[-1],
            "path": "/" + "/".join(path.strip("/").split("/")[:-1])
            if "/" in path.strip("/")
            else "/",
        }
        # Newer API uses projectId + folderName
        alt = {
            "projectId": project_id,
            "environment": environment,
            "name": path.strip("/").split("/")[-1],
            "path": "/"
            if path.count("/") <= 1
            else "/" + "/".join(path.strip("/").split("/")[:-1]),
        }
        for payload, api in (
            (body, "/api/v2/folders"),
            (alt, "/api/v2/folders"),
            (alt, "/api/v1/folders"),
        ):
            try:
                self._req("POST", api, payload)
                return
            except RuntimeError as e:
                msg = str(e).lower()
                if "already" in msg or "409" in msg or "exist" in msg:
                    return
                continue

    def upsert_secret(
        self,
        project_id: str,
        environment: str,
        path: str,
        key: str,
        value: str,
    ) -> None:
        secret_path = path if path.startswith("/") else f"/{path}"
        create_body = {
            "workspaceId": project_id,
            "environment": environment,
            "secretPath": secret_path,
            "secretKey": key,
            "secretValue": value,
            "type": "shared",
        }
        update_body = {
            "workspaceId": project_id,
            "environment": environment,
            "secretPath": secret_path,
            "secretValue": value,
            "type": "shared",
        }
        # Try create; on conflict update.
        try:
            self._req("POST", "/api/v3/secrets/raw/" + urllib.parse.quote(key), create_body)
            return
        except RuntimeError:
            pass
        try:
            self._req(
                "PATCH",
                "/api/v3/secrets/raw/" + urllib.parse.quote(key),
                update_body,
            )
            return
        except RuntimeError:
            pass
        # Fallback create without /raw
        try:
            self._req(
                "POST",
                f"/api/v3/secrets/{urllib.parse.quote(key)}",
                {
                    "workspaceId": project_id,
                    "environment": environment,
                    "secretPath": secret_path,
                    "secretValue": value,
                    "type": "shared",
                },
            )
        except RuntimeError as e:
            raise RuntimeError(f"upsert {key} @ {secret_path}: {e}") from e


def login_universal(base: str, client_id: str, client_secret: str) -> str:
    body = json.dumps(
        {"clientId": client_id, "clientSecret": client_secret}
    ).encode()
    req = urllib.request.Request(
        f"{base.rstrip('/')}/api/v1/auth/universal-auth/login",
        data=body,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    # Also try /api/v1/universal-auth/login
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode())["accessToken"]
    except urllib.error.HTTPError:
        req2 = urllib.request.Request(
            f"{base.rstrip('/')}/api/v1/universal-auth/login",
            data=body,
            method="POST",
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req2, timeout=60) as resp:
            return json.loads(resp.read().decode())["accessToken"]


def login_email(base: str, email: str, password: str) -> str:
    body = json.dumps({"email": email, "password": password}).encode()
    for path in (
        "/api/v1/auth/login",
        "/api/v3/auth/login",
        "/api/v1/auth/email/login",
    ):
        req = urllib.request.Request(
            f"{base.rstrip('/')}{path}",
            data=body,
            method="POST",
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = json.loads(resp.read().decode())
                for k in ("accessToken", "token", "access_token"):
                    if k in data:
                        return data[k]
                if "mfaToken" in data:
                    raise RuntimeError(
                        "MFA required — use Universal Auth machine identity instead"
                    )
        except urllib.error.HTTPError:
            continue
    raise RuntimeError("email/password login failed — check credentials or use Universal Auth")


def load_yaml(path: Path) -> Any:
    with path.open() as f:
        return yaml.safe_load(f) or {}


def main() -> int:
    base = os.environ.get("INFISICAL_URL", "http://192.168.68.25:8090")
    secrets_path = Path(os.environ.get("SECRETS_FILE", str(DEFAULT_SECRETS)))
    map_path = Path(os.environ.get("SEED_MAP", str(DEFAULT_MAP)))
    dry = os.environ.get("DRY_RUN", "") in ("1", "true", "yes")
    org_id = os.environ.get("INFISICAL_ORG_ID", "")

    if not secrets_path.is_file():
        print(f"Missing secrets file: {secrets_path}", file=sys.stderr)
        print("Copy secrets.example.yml → secrets.yml and fill values.", file=sys.stderr)
        return 1
    if not map_path.is_file():
        print(f"Missing seed map: {map_path}", file=sys.stderr)
        return 1

    secrets = load_yaml(secrets_path)
    seed_map = load_yaml(map_path)
    env_slug = seed_map.get("default_environment", "prod")

    client_id = os.environ.get("INFISICAL_UNIVERSAL_AUTH_CLIENT_ID", "")
    client_secret = os.environ.get("INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET", "")
    email = os.environ.get("INFISICAL_EMAIL", "")
    password = os.environ.get("INFISICAL_PASSWORD", "")

    if dry:
        print(f"DRY_RUN: would seed from {secrets_path} using map {map_path}")
        for proj in seed_map.get("projects", []):
            print(f"  project {proj['slug']}: {len(proj.get('secrets', []))} secrets")
        return 0

    if client_id and client_secret:
        token = login_universal(base, client_id, client_secret)
        print("Authenticated via Universal Auth")
    elif email and password:
        token = login_email(base, email, password)
        print("Authenticated via email/password")
    else:
        print(
            "Set INFISICAL_UNIVERSAL_AUTH_CLIENT_ID/SECRET or INFISICAL_EMAIL/PASSWORD",
            file=sys.stderr,
        )
        return 1

    client = InfisicalClient(base, token)
    existing = client.list_workspaces()
    by_slug = {
        (w.get("slug") or w.get("name") or "").lower(): w for w in existing
    }

    created_paths: set[tuple[str, str]] = set()

    for proj in seed_map.get("projects", []):
        slug = proj["slug"]
        name = proj.get("name", slug)
        ws = by_slug.get(slug.lower())
        if not ws:
            print(f"Creating project {slug}…")
            created = client.create_workspace(name, slug, org_id)
            # Normalize response
            if "workspace" in created:
                ws = created["workspace"]
            elif "project" in created:
                ws = created["project"]
            else:
                ws = created
            by_slug[slug.lower()] = ws
            print(f"  created {slug}")
        else:
            print(f"Project {slug} exists")

        project_id = ws.get("id") or ws.get("_id") or ws.get("workspaceId")
        if not project_id:
            print(f"  WARN: no project id for {slug}, skip secrets", file=sys.stderr)
            continue

        for item in proj.get("secrets", []):
            key = item["key"]
            from_key = item["from"]
            path = item.get("path", "/")
            optional = item.get("optional", False)
            value = secrets.get(from_key)
            if value is None or value == "" or (
                isinstance(value, str) and value.startswith("replace-with")
            ):
                if optional:
                    print(f"  skip optional {slug}{path}/{key} (unset)")
                    continue
                print(
                    f"  WARN: missing {from_key} for {slug}{path}/{key}",
                    file=sys.stderr,
                )
                continue

            folder_key = (project_id, path)
            if path not in ("", "/") and folder_key not in created_paths:
                client.ensure_folder(project_id, env_slug, path)
                created_paths.add(folder_key)

            print(f"  upsert {slug}{path} → {key}")
            client.upsert_secret(
                project_id, env_slug, path, key, str(value)
            )

    print("Done. Create a machine identity in Infisical UI for cluster sync")
    print("and apply platform/secrets InfisicalSecret CRs (see docs).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
