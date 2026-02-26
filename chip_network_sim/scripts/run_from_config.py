#!/usr/bin/env python3
"""Launch orchestrator from JSON config."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def get(data: dict, path: str, default=None):
    cur = data
    for part in path.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return default
        cur = cur[part]
    return cur


def main() -> int:
    parser = argparse.ArgumentParser(description="Run chip-network simulation from JSON config")
    parser.add_argument("-cfg", "--config", required=True, help="Path to network JSON config")
    parser.add_argument(
        "--orchestrator-bin",
        default=str(Path(__file__).resolve().parents[1] / "build" / "orchestrator"),
        help="Path to compiled orchestrator binary",
    )
    parser.add_argument(
        "--chip-bin",
        default=str(Path(__file__).resolve().parents[1] / "build" / "chip"),
        help="Path to compiled chip binary",
    )
    args = parser.parse_args()

    with open(args.config, "r", encoding="utf-8") as f:
        cfg = json.load(f)

    rows = get(cfg, "grid.rows")
    cols = get(cfg, "grid.cols")
    ticks = get(cfg, "runtime.ticks")
    if rows is None or cols is None or ticks is None:
        print("config must define grid.rows, grid.cols, and runtime.ticks", file=sys.stderr)
        return 2

    sync = get(cfg, "runtime.sync_mode", "barrier_ack")
    route = get(cfg, "runtime.route", "east")
    fifo_depth = str(get(cfg, "runtime.fifo_depth", 32))
    gen_ppm = str(get(cfg, "traffic.gen_ppm", 100000))
    seed = str(get(cfg, "runtime.seed", 1))
    ack_window = str(get(cfg, "runtime.ack_window", 4))
    startup_ms = str(get(cfg, "runtime.startup_ms", 350))
    ack_timeout_ms = str(get(cfg, "runtime.ack_timeout_ms", 5000))

    chip_bin = get(cfg, "runtime.chip_bin", args.chip_bin)

    cmd = [
        args.orchestrator_bin,
        "-rows",
        str(rows),
        "-cols",
        str(cols),
        "-ticks",
        str(ticks),
        "-sync",
        sync,
        "-route",
        route,
        "-fifo_depth",
        fifo_depth,
        "-gen_ppm",
        gen_ppm,
        "-seed",
        seed,
        "-ack_window",
        ack_window,
        "-startup_ms",
        startup_ms,
        "-ack_timeout_ms",
        ack_timeout_ms,
        "-chip_bin",
        chip_bin,
    ]

    print(" ".join(cmd))
    return subprocess.call(cmd)


if __name__ == "__main__":
    raise SystemExit(main())
