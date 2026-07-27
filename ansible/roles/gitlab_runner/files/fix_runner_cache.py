#!/usr/bin/env python3
"""Rewrite [[runners]].cache to a single S3 block (idempotent)."""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--config", required=True)
    p.add_argument("--server", required=True)
    p.add_argument("--access-key", required=True)
    p.add_argument("--secret-key", required=True)
    p.add_argument("--bucket", required=True)
    p.add_argument("--location", required=True)
    p.add_argument("--insecure", required=True, choices=("true", "false"))
    args = p.parse_args()

    path = Path(args.config)
    text = path.read_text()
    original = text

    text = re.sub(
        r"\n?# BEGIN ANSIBLE MANAGED RUNNER CACHE\n.*?\# END ANSIBLE MANAGED RUNNER CACHE\n?",
        "\n",
        text,
        flags=re.S,
    )

    cache_block = f"""  [runners.cache]
    Type = "s3"
    Shared = true
    MaxUploadedArchiveSize = 0
    [runners.cache.s3]
      ServerAddress = "{args.server}"
      AccessKey = "{args.access_key}"
      SecretKey = "{args.secret_key}"
      BucketName = "{args.bucket}"
      BucketLocation = "{args.location}"
      Insecure = {args.insecure}
"""
    replacement = "\n" + cache_block.rstrip() + "\n"
    text2, n = re.subn(
        r"\n  \[runners\.cache\].*?(?=\n  \[runners\.docker\])",
        replacement,
        text,
        count=1,
        flags=re.S,
    )
    if n == 0:
        text2, n = re.subn(
            r"(\n  \[runners\.docker\])",
            replacement + r"\1",
            text,
            count=1,
        )
    if n == 0:
        print("could not locate [runners.docker] in config.toml", file=sys.stderr)
        return 1

    if text2 != original:
        path.write_text(text2)
        print("changed")
    else:
        print("ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
