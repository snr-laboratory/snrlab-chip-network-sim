#!/usr/bin/env python3
"""Launch orchestrator from JSON config."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Dict


def get(data: dict, path: str, default=None):
    cur = data
    for part in path.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return default
        cur = cur[part]
    return cur


def parse_chip_gen_overrides(values: list[str] | None) -> Dict[int, int]:
    overrides: Dict[int, int] = {}
    if not values:
        return overrides
    for raw in values:
        parts = raw.split(":", 1)
        if len(parts) != 2:
            raise ValueError(f"invalid --chip-gen '{raw}' (expected id:ppm)")
        chip_id = int(parts[0])
        gen_ppm = int(parts[1])
        if chip_id < 0:
            raise ValueError(f"invalid chip id in --chip-gen '{raw}'")
        if gen_ppm < 0 or gen_ppm > 1_000_000:
            raise ValueError(f"invalid gen_ppm in --chip-gen '{raw}' (expected 0..1000000)")
        overrides[chip_id] = gen_ppm
    return overrides


def main() -> int:
    parser = argparse.ArgumentParser(description="Run chip-network simulation from JSON config")
    parser.add_argument("-cfg", "--config", required=True, help="Path to network JSON config")
    parser.add_argument("--fifo-depth", type=int, default=None, help="Override runtime.fifo_depth")
    parser.add_argument(
        "--chip-gen",
        action="append",
        default=None,
        help="Per-chip generation override, format id:ppm (repeatable)",
    )
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
    try:
        chip_gen_overrides = parse_chip_gen_overrides(args.chip_gen)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    rows = get(cfg, "grid.rows")
    cols = get(cfg, "grid.cols")
    ticks = get(cfg, "runtime.ticks")
    if rows is None or cols is None or ticks is None:
        print("config must define grid.rows, grid.cols, and runtime.ticks", file=sys.stderr)
        return 2

    route = get(cfg, "runtime.route", "east")
    fifo_depth_val = int(get(cfg, "runtime.fifo_depth", 32))
    if args.fifo_depth is not None:
        if args.fifo_depth <= 0:
            print("--fifo-depth must be > 0", file=sys.stderr)
            return 2
        fifo_depth_val = args.fifo_depth
    fifo_depth = str(fifo_depth_val)
    gen_ppm = str(get(cfg, "traffic.gen_ppm", 100000))
    seed = str(get(cfg, "runtime.seed", 1))
    startup_ms = str(get(cfg, "runtime.startup_ms", 350))
    ack_timeout_ms = str(get(cfg, "runtime.ack_timeout_ms", 5000))

    chip_bin = get(cfg, "runtime.chip_bin", args.chip_bin)
    trace_dir = get(cfg, "runtime.trace_dir")
    trace_run_id = get(cfg, "runtime.trace_run_id")

    cmd = [
        args.orchestrator_bin,
        "-rows",
        str(rows),
        "-cols",
        str(cols),
        "-ticks",
        str(ticks),
        "-fifo_depth",
        fifo_depth,
        "-gen_ppm",
        gen_ppm,
        "-seed",
        seed,
        "-startup_ms",
        startup_ms,
        "-ack_timeout_ms",
        ack_timeout_ms,
        "-chip_bin",
        chip_bin,
    ]

    routes = cfg.get("routes")
    if routes is None:
        cmd.extend(["-route", route])
    else:
        normalized_routes = []
        if not isinstance(routes, list):
            print("routes must be a list of {id,input_id,out_id}", file=sys.stderr)
            return 2
        for entry in routes:
            if not isinstance(entry, dict):
                print("route entry must be an object", file=sys.stderr)
                return 2
            normalized_routes.append(entry)
        for entry in sorted(normalized_routes, key=lambda x: int(x.get("id", -1))):
            if "id" not in entry or "input_id" not in entry or "out_id" not in entry:
                print("route entry must include id, input_id, out_id", file=sys.stderr)
                return 2
            spec = f"{entry['id']}:{entry['input_id']}:{entry['out_id']}"
            cmd.extend(["-chip_route", spec])
            if "gen_ppm" in entry or int(entry["id"]) in chip_gen_overrides:
                gen_val = int(entry.get("gen_ppm", get(cfg, "traffic.gen_ppm", 100000)))
                if int(entry["id"]) in chip_gen_overrides:
                    gen_val = chip_gen_overrides[int(entry["id"])]
                spec_gen = f"{entry['id']}:{gen_val}"
                cmd.extend(["-chip_gen", spec_gen])

    if trace_dir:
        cmd.extend(["-trace_dir", str(trace_dir)])
    if trace_run_id:
        cmd.extend(["-trace_run_id", str(trace_run_id)])

    print(" ".join(cmd))
    return subprocess.call(cmd)


if __name__ == "__main__":
    raise SystemExit(main())
