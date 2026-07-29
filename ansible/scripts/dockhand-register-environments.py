#!/usr/bin/env python3
"""Register Dockhand environments via API (no UI) and mint Hawser tokens.

Official path (confirmed against Dockhand 1.0.38 + Finsys/dockhand#248):
  GET/POST/DELETE  /api/environments
  POST             /api/hawser/tokens   {"name","environmentId"} → plaintext token once

Auth disabled (default first launch): no Bearer needed.
Auth enabled: pass DOCKHAND_API_TOKEN or --token (Bearer).

Writes tokens to a gitignored JSON file for Ansible hawser role consumption.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

DEFAULT_BASE = os.environ.get("DOCKHAND_URL", "http://192.168.68.22:3000")
DEFAULT_TOKEN_FILE = Path(
    os.environ.get(
        "DOCKHAND_HAWSER_TOKENS_FILE",
        Path(__file__).resolve().parents[1] / "files" / "dockhand-hawser-tokens.json",
    )
)

# Lab Docker engines for lab-home-k8s (no database/monitoring/sonar/elastic VMs).
LAB_ENVIRONMENTS: list[dict[str, Any]] = [
    {
        "name": "dockhand-local",
        "connectionType": "socket",
        "socketPath": "/var/run/docker.sock",
        "labels": ["lab", "local"],
        "ansible_host": None,  # no remote agent
    },
    {
        "name": "docker-01",
        "connectionType": "hawser-edge",
        "labels": ["lab", "docker"],
        "ansible_host": "docker-01",
        "agent_name": "docker-01",
    },
    {
        "name": "infra-01",
        "connectionType": "hawser-edge",
        "labels": ["lab", "infra"],
        "ansible_host": "infra-01",
        "agent_name": "infra-01",
    },
]


class DockhandClient:
    def __init__(self, base: str, api_token: str | None = None) -> None:
        self.base = base.rstrip("/")
        self.api_token = api_token

    def _request(
        self,
        method: str,
        path: str,
        body: dict[str, Any] | None = None,
    ) -> Any:
        data = None
        headers = {"Accept": "application/json"}
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        if self.api_token:
            headers["Authorization"] = f"Bearer {self.api_token}"
        req = urllib.request.Request(
            f"{self.base}{path}",
            data=data,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                raw = resp.read().decode() or "null"
                return json.loads(raw)
        except urllib.error.HTTPError as e:
            err_body = e.read().decode(errors="replace")
            raise SystemExit(f"{method} {path} → HTTP {e.code}: {err_body}") from e

    def list_environments(self) -> list[dict[str, Any]]:
        result = self._request("GET", "/api/environments")
        if not isinstance(result, list):
            raise SystemExit(f"Unexpected environments payload: {result!r}")
        return result

    def create_environment(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self._request("POST", "/api/environments", payload)

    def mint_hawser_token(self, environment_id: int, name: str) -> dict[str, Any]:
        return self._request(
            "POST",
            "/api/hawser/tokens",
            {"name": name, "environmentId": environment_id},
        )


def ensure_environment(
    client: DockhandClient,
    desired: dict[str, Any],
    existing_by_name: dict[str, dict[str, Any]],
) -> tuple[dict[str, Any], bool]:
    name = desired["name"]
    if name in existing_by_name:
        return existing_by_name[name], False
    payload = {
        "name": name,
        "connectionType": desired["connectionType"],
        "labels": desired.get("labels") or [],
    }
    if desired["connectionType"] == "socket":
        payload["socketPath"] = desired.get("socketPath", "/var/run/docker.sock")
    created = client.create_environment(payload)
    return created, True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default=DEFAULT_BASE, help="Dockhand base URL")
    parser.add_argument(
        "--token",
        default=os.environ.get("DOCKHAND_API_TOKEN", ""),
        help="Bearer API token if Dockhand auth is enabled",
    )
    parser.add_argument(
        "--tokens-file",
        type=Path,
        default=DEFAULT_TOKEN_FILE,
        help="Where to write Hawser agent tokens (gitignored)",
    )
    parser.add_argument(
        "--mint-tokens",
        action="store_true",
        help="Mint new Hawser tokens for edge envs (overwrites tokens file entries)",
    )
    args = parser.parse_args()

    client = DockhandClient(args.url, args.token or None)
    existing = {e["name"]: e for e in client.list_environments()}

    token_store: dict[str, Any] = {}
    if args.tokens_file.exists():
        token_store = json.loads(args.tokens_file.read_text())

    print(f"Dockhand: {args.url}")
    for desired in LAB_ENVIRONMENTS:
        env, created = ensure_environment(client, desired, existing)
        existing[env["name"]] = env
        status = "created" if created else "exists"
        print(f"  [{status}] {env['name']} id={env['id']} type={env['connectionType']}")

        if desired["connectionType"] != "hawser-edge":
            continue
        if not args.mint_tokens and desired["name"] in token_store.get("agents", {}):
            print(f"    token: kept (use --mint-tokens to rotate)")
            continue
        if not args.mint_tokens and not created:
            # Existing edge env without a stored token — must mint to deploy agent
            print(f"    token: missing locally — minting")
        minted = client.mint_hawser_token(int(env["id"]), f"ansible-{desired['name']}")
        plaintext = minted.get("token")
        if not plaintext:
            raise SystemExit(f"No token in mint response: {minted}")
        token_store.setdefault("agents", {})[desired["name"]] = {
            "environment_id": env["id"],
            "ansible_host": desired.get("ansible_host"),
            "agent_name": desired.get("agent_name", desired["name"]),
            "token": plaintext,
            "token_id": minted.get("tokenId"),
        }
        print(f"    token: minted (saved to {args.tokens_file})")

    token_store["dockhand_url"] = args.url
    # Agents on LAN should dial Dockhand over ws:// (Access on public hostname blocks agents)
    token_store["dockhand_server_url"] = os.environ.get(
        "DOCKHAND_SERVER_URL",
        "ws://192.168.68.22:3000/api/hawser/connect",
    )
    args.tokens_file.parent.mkdir(parents=True, exist_ok=True)
    args.tokens_file.write_text(json.dumps(token_store, indent=2) + "\n")
    args.tokens_file.chmod(0o600)
    print(f"Wrote {args.tokens_file}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
