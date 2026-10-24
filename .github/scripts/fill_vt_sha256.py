#!/usr/bin/env python3
"""Replace VT_SHA256_<filename> placeholders with file SHA-256 digests.

Also appends a SHA-256 checksum table for every asset under the assets directory.
"""

from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path


# Filenames only — stop before URL path (/detection) or query (?start=...).
PLACEHOLDER_RE = re.compile(r"VT_SHA256_([A-Za-z0-9._+-]+)")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def collect_assets(assets_dir: Path) -> dict[str, Path]:
    """Map basename -> path (first wins). Prefer shallower paths on collision."""
    by_name: dict[str, Path] = {}
    for path in sorted(assets_dir.rglob("*"), key=lambda p: (len(p.parts), str(p))):
        if not path.is_file():
            continue
        # Skip helper text / checksum sidecars if present
        if path.name.endswith(".sha256") or path.name in {"SHA256SUMS", "checksums.txt"}:
            continue
        by_name.setdefault(path.name, path)
    return by_name


def main() -> int:
    if len(sys.argv) < 3:
        print(f"usage: {sys.argv[0]} <release.md> <assets-dir>", file=sys.stderr)
        return 2

    notes_path = Path(sys.argv[1])
    assets_dir = Path(sys.argv[2])
    if not notes_path.is_file():
        print(f"error: {notes_path} does not exist", file=sys.stderr)
        return 1
    if not assets_dir.is_dir():
        print(f"error: {assets_dir} is not a directory", file=sys.stderr)
        return 1

    assets = collect_assets(assets_dir)
    digests: dict[str, str] = {}
    for name, path in sorted(assets.items()):
        digests[name] = sha256_file(path)
        print(f"{name}: {digests[name]}")

    # Case-insensitive lookup for Windows .Msix vs .msix, etc.
    digests_ci = {name.lower(): digest for name, digest in digests.items()}

    text = notes_path.read_text()
    replaced = 0
    missing: list[str] = []

    def replace_placeholder(match: re.Match[str]) -> str:
        nonlocal replaced
        name = match.group(1)
        digest = digests.get(name) or digests_ci.get(name.lower())
        if digest:
            replaced += 1
            return digest
        missing.append(name)
        return match.group(0)

    text = PLACEHOLDER_RE.sub(replace_placeholder, text)

    # Checksum section for every file that was actually built/uploaded.
    if digests:
        lines = [
            "",
            "## SHA-256 checksums",
            "",
            "| File | SHA-256 |",
            "| --- | --- |",
        ]
        for name, digest in sorted(digests.items()):
            lines.append(f"| `{name}` | `{digest}` |")
        lines.append("")
        # Replace a previous auto section if the notes are regenerated in-place.
        text = re.sub(
            r"\n## SHA-256 checksums\n.*?(?=\n## |\n<details|\Z)",
            "\n",
            text,
            count=1,
            flags=re.DOTALL,
        )
        text = text.rstrip() + "\n" + "\n".join(lines)

    notes_path.write_text(text)
    print(f"replaced {replaced} VT_SHA256 placeholders")
    if missing:
        unique_missing = sorted(set(missing))
        print(
            "warning: no asset for placeholders: " + ", ".join(unique_missing),
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
