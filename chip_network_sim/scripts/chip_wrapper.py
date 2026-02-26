#!/usr/bin/env python3
"""Thin Python wrapper for the C99 chip runtime."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Launch a single chip runtime")
    parser.add_argument(
        "--chip-bin",
        default=str(Path(__file__).resolve().parents[1] / "build" / "chip"),
        help="Path to compiled chip binary",
    )
    parser.add_argument(
        "--verilator-mode",
        action="store_true",
        help="Placeholder toggle for future Verilator backend selection",
    )
    args, passthrough = parser.parse_known_args()

    chip_bin = Path(args.chip_bin)
    if not chip_bin.exists():
        print(f"chip binary not found: {chip_bin}", file=sys.stderr)
        return 1

    env = os.environ.copy()
    if args.verilator_mode:
        env["CHIPSIM_BACKEND"] = "verilator"

    cmd = [str(chip_bin), *passthrough]
    return subprocess.call(cmd, env=env)


if __name__ == "__main__":
    raise SystemExit(main())
