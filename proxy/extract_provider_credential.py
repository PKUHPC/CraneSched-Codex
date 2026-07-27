#!/usr/bin/env python3
"""Extract one pinned Codex provider credential without printing it.

This intentionally supports only the simple TOML shape used by Codex provider
tables. Refusing unsupported syntax is safer here than silently extracting a
credential from the wrong table or endpoint.
"""

import argparse
import os
import re
import stat


BARE_KEY = r"[A-Za-z0-9_-]+"


def parse_simple_string(raw: str, field: str) -> str:
    value = raw.strip()
    if len(value) < 2 or value[0] not in {'"', "'"} or value[-1] != value[0]:
        raise ValueError(f"{field} must be a single-line quoted TOML string")
    inner = value[1:-1]
    if value[0] in inner or "\\" in inner or "\n" in inner or "\r" in inner:
        raise ValueError(f"{field} uses unsupported quoting or escapes")
    return inner


def strip_comment(line: str) -> str:
    quote = None
    for index, character in enumerate(line):
        if quote is None and character in {'"', "'"}:
            quote = character
        elif quote == character:
            quote = None
        elif quote is None and character == "#":
            return line[:index]
    if quote is not None:
        raise ValueError("unterminated quoted string")
    return line


def contains_multiline_string(text: str) -> bool:
    for line in text.splitlines():
        quote = None
        index = 0
        while index < len(line):
            character = line[index]
            if quote is None:
                if character == "#":
                    break
                if line.startswith(('"""', "'''"), index):
                    return True
                if character in {'"', "'"}:
                    quote = character
            elif quote == '"' and character == "\\":
                index += 2
                continue
            elif character == quote:
                quote = None
            index += 1
    return False


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
    if not re.fullmatch(BARE_KEY, provider_name):
        raise ValueError("provider name must be a bare TOML key")
    if contains_multiline_string(text):
        raise ValueError("multiline TOML strings are not supported in credential sources")

    expected_section = f"model_providers.{provider_name}"
    current_section = None
    found_section = False
    values: dict[str, str] = {}

    expected_header = re.compile(
        rf"\[\s*model_providers\s*\.\s*{re.escape(provider_name)}\s*\]"
    )

    for line_number, original_line in enumerate(text.splitlines(), start=1):
        left_stripped = original_line.lstrip()
        if left_stripped.startswith("["):
            # Any table or array-of-tables header ends the current provider.
            # Only the pinned, bare-key provider header needs to be understood;
            # unrelated TOML may use syntax outside this extractor's subset.
            header = left_stripped.split("#", 1)[0].strip()
            if expected_header.fullmatch(header):
                if found_section:
                    raise ValueError(f"duplicate provider section at line {line_number}")
                found_section = True
                current_section = expected_section
            else:
                current_section = None
            continue

        if current_section != expected_section:
            continue

        key_match = re.match(rf"\s*({BARE_KEY})\s*=", original_line)
        if not key_match:
            continue
        key = key_match.group(1)
        if key not in {"base_url", "experimental_bearer_token"}:
            continue
        line = strip_comment(original_line).strip()
        assignment = re.fullmatch(rf"({re.escape(key)})\s*=\s*(.+)", line)
        if not assignment:
            raise ValueError(f"unsupported {key} syntax at line {line_number}")
        raw_value = assignment.group(2)
        if key in values:
            raise ValueError(f"duplicate {key} at line {line_number}")
        values[key] = parse_simple_string(raw_value, key)

    if not found_section:
        raise ValueError(f"provider section [{expected_section}] was not found")
    missing = {"base_url", "experimental_bearer_token"} - values.keys()
    if missing:
        raise ValueError(f"provider is missing required fields: {', '.join(sorted(missing))}")
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
