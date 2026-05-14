#!/usr/bin/env python3
"""Thin Python wrapper for the C99 chip runtime."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="Launch a single chip runtime")
    parser.add_argument(
        "--chip-bin",
        default=None,
        help="Path to compiled chip binary (overrides --rtl)",
    )
    parser.add_argument(
        "--rtl",
        action="store_true",
        help="Use build/chip_rtl instead of build/chip",
    )
    args, passthrough = parser.parse_known_args()

    if args.chip_bin is not None:
        chip_bin = Path(args.chip_bin)
    else:
        chip_bin = repo_root / "build" / ("chip_rtl" if args.rtl else "chip")

    if not chip_bin.exists():
        print(f"chip binary not found: {chip_bin}", file=sys.stderr)
        return 1

    cmd = [str(chip_bin), *passthrough]
    return subprocess.call(cmd)


if __name__ == "__main__":
    raise SystemExit(main())
