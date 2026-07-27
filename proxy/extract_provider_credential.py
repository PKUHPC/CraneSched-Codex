#!/usr/bin/env python3
"""Extract one pinned Codex provider credential without printing it."""

import argparse
import os
import re
import stat

try:
    import tomllib
except ModuleNotFoundError:  # Python 3.9 on EL9
    import tomli as tomllib


def read_secure_text(path: str) -> str:
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags)
    try:
        source_stat = os.fstat(descriptor)
        if not stat.S_ISREG(source_stat.st_mode):
            raise ValueError("source config must be a regular file")
        if source_stat.st_mode & 0o077:
            raise ValueError("source config must not be group- or world-accessible")
        if source_stat.st_uid not in {0, os.geteuid()}:
            raise ValueError("source config must be owned by root or the current user")
        with os.fdopen(descriptor, "r", encoding="utf-8", closefd=False) as handle:
            return handle.read()
    finally:
        os.close(descriptor)


def extract_provider(text: str, provider_name: str) -> tuple[str, str]:
    document = tomllib.loads(text)
    providers = document.get("model_providers")
    if not isinstance(providers, dict):
        raise ValueError("source config has no model_providers table")
    provider = providers.get(provider_name)
    if not isinstance(provider, dict):
        raise ValueError(f"provider section [model_providers.{provider_name}] was not found")

    values = {}
    for field in ("base_url", "experimental_bearer_token"):
        value = provider.get(field)
        if not isinstance(value, str) or not value:
            raise ValueError(f"provider field {field} must be a non-empty string")
        values[field] = value
    return values["base_url"].rstrip("/"), values["experimental_bearer_token"]


def write_secret_atomic(target: str, token: str) -> None:
    temporary = f"{target}.tmp.{os.getpid()}"
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(temporary, flags, 0o400)
    try:
        with os.fdopen(descriptor, "wb", closefd=True) as handle:
            handle.write(token.encode("ascii"))
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, target)
        os.chmod(target, 0o400, follow_symlinks=False)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--provider", required=True)
    parser.add_argument("--expected-base-url", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    try:
        text = read_secure_text(args.source)
        base_url, token = extract_provider(text, args.provider)
        if base_url != args.expected_base_url.rstrip("/"):
            raise ValueError(
                f"provider endpoint mismatch: expected {args.expected_base_url!r}, "
                f"got {base_url!r}"
            )
        if not re.fullmatch(r"[A-Za-z0-9_-]+", token):
            raise ValueError("provider bearer token is empty or incompatible with the proxy")
        write_secret_atomic(args.output, token)
    except (OSError, UnicodeError, ValueError) as error:
        raise SystemExit(f"credential extraction failed: {error}") from error


if __name__ == "__main__":
    main()
