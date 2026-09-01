#!/usr/bin/env python3
"""Freeze the current audit scope without rewriting the historical snapshot."""

from __future__ import annotations

import runpy
from pathlib import Path


AUDIT = Path(__file__).resolve().parent
ROOT = AUDIT.parents[2]
SOURCE = ROOT / ".codex/runtime/dependency-supply-chain-audit-20260822/_freeze_scope.py"


def main() -> None:
    namespace = runpy.run_path(str(SOURCE), run_name="audit_freeze_library")
    freeze = namespace["main"]
    freeze.__globals__["AUDIT"] = AUDIT
    freeze.__globals__["AUDIT_ID"] = AUDIT.name
    freeze()


if __name__ == "__main__":
    main()
