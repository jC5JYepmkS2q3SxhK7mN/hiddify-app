#!/usr/bin/env python3
"""Replace VT_SHA256_<filename> placeholders with file SHA-256 digests."""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    if len(sys.argv) < 3:
        print(f"usage: {sys.argv[0]} <release.md> <assets-dir>", file=sys.stderr)
        return 2

    notes_path = Path(sys.argv[1])
    assets_dir = Path(sys.argv[2])
    text = notes_path.read_text()

    for path in sorted(assets_dir.iterdir()):
        if not path.is_file():
            continue
        placeholder = f"VT_SHA256_{path.name}"
        if placeholder not in text:
            continue
        digest = sha256_file(path)
        text = text.replace(placeholder, digest)
        print(f"{path.name}: {digest}")

    notes_path.write_text(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
