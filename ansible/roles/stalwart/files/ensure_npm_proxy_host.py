#!/usr/bin/env python3
"""Ensure Nginx Proxy Manager proxy-host (+ optional locations / advanced_config)."""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request


def request(method: str, url: str, token: str | None = None, body: dict | None = None):
    data = None if body is None else json.dumps(body).encode()
    headers = {"Accept": "application/json", "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read().decode() or "null"
        return json.loads(raw)


def main() -> int:
    base = os.environ["NPM_URL"].rstrip("/")
    email = os.environ["NPM_EMAIL"]
    password = os.environ["NPM_PASSWORD"]
    domains = json.loads(os.environ["DOMAINS"])
    forward_host = os.environ["FORWARD_HOST"]
    forward_port = int(os.environ["FORWARD_PORT"])
    advanced_config = os.environ.get("ADVANCED_CONFIG", "")
    locations = json.loads(os.environ.get("LOCATIONS", "[]"))

    token = request(
        "POST",
        f"{base}/api/tokens",
        body={"identity": email, "secret": password},
    )["token"]

    hosts = request("GET", f"{base}/api/nginx/proxy-hosts", token=token)
    want = set(domains)
    existing_id = None
    for host in hosts:
        if want & set(host.get("domain_names") or []):
            existing_id = host["id"]
            break

    payload = {
        "domain_names": domains,
        "forward_scheme": "http",
        "forward_host": forward_host,
        "forward_port": forward_port,
        "access_list_id": "0",
        "certificate_id": "0",
        "meta": {},
        "advanced_config": advanced_config,
        "locations": locations,
        "block_exploits": True,
        "caching_enabled": False,
        "allow_websocket_upgrade": True,
        "http2_support": False,
        "hsts_enabled": False,
        "hsts_subdomains": False,
        "ssl_forced": False,
        "enabled": True,
    }

    if existing_id is not None:
        request("PUT", f"{base}/api/nginx/proxy-hosts/{existing_id}", token=token, body=payload)
        print(f"updated proxy-host id={existing_id}")
    else:
        request("POST", f"{base}/api/nginx/proxy-hosts", token=token, body=payload)
        print("created proxy-host")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except urllib.error.HTTPError as exc:
        sys.stderr.write(exc.read().decode(errors="replace") + "\n")
        raise
