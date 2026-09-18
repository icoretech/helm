#!/usr/bin/env python3
"""Fail when a workflow action is not pinned to an immutable commit SHA."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ACTION = re.compile(r"^\s*-?\s*uses:\s*([^\s#]+)\s*(?:#.*)?$")
SHA = re.compile(r"^[0-9a-f]{40}$")


def main() -> int:
    failures: list[str] = []

    for workflow in sorted(Path(".github/workflows").glob("*.y*ml")):
        for line_number, line in enumerate(workflow.read_text().splitlines(), 1):
            match = ACTION.match(line)
            if not match:
                continue

            target = match.group(1)
            if target.startswith("./"):
                continue

            action, separator, reference = target.partition("@")
            if not separator or not SHA.fullmatch(reference):
                failures.append(
                    f"{workflow}:{line_number}: {action or target} must use a full 40-character commit SHA"
                )

    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1

    print("workflow actions are pinned to immutable commits")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
