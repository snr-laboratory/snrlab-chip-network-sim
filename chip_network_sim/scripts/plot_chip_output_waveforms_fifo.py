#!/usr/bin/env python3
"""Plot clock + per-chip output pulse waveforms from a trace run."""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path
from typing import Dict, List

import matplotlib.pyplot as plt

MAGIC = b"CTRACE01"
HEADER_SIZE = 64
ROW_SIZE = 24
ROW_STRUCT = struct.Struct("<QHHIQ")
EV_GEN_LOCAL = 1
EV_ENQ_LOCAL_OK = 2
EV_ENQ_NEIGH_OK = 4
EV_DEQ_OUT = 6
Y_MIN = 0.0
Y_MAX = 1.3
TRACE_LINEWIDTH = 2.8


def load_manifest(run_dir: Path) -> dict:
    manifest_path = run_dir / "manifest.json"
    if not manifest_path.exists():
        raise FileNotFoundError(f"missing manifest: {manifest_path}")
    with manifest_path.open("r", encoding="utf-8") as f:
        return json.load(f)


def load_rows(trace_path: Path) -> List[tuple[int, int, int]]:
    data = trace_path.read_bytes()
    if len(data) < HEADER_SIZE:
        raise ValueError(f"trace too short: {trace_path}")

    if data[:8] != MAGIC:
        raise ValueError(f"bad trace magic: {trace_path}")

    header_size = int.from_bytes(data[14:16], "little")
    record_size = int.from_bytes(data[16:18], "little")
    if header_size != HEADER_SIZE or record_size != ROW_SIZE:
        raise ValueError(
            f"unexpected row/header size in {trace_path}: {header_size}/{record_size}"
        )

    payload = data[HEADER_SIZE:]
    if len(payload) % ROW_SIZE != 0:
        raise ValueError(f"corrupt row alignment in {trace_path}")

    rows: List[tuple[int, int, int]] = []
    for off in range(0, len(payload), ROW_SIZE):
        tick, ev, _r0, occ, _word = ROW_STRUCT.unpack_from(payload, off)
        rows.append((int(tick), int(ev), int(occ)))
    return rows


def infer_route_order(chips: List[dict]) -> List[int]:
    by_id: Dict[int, dict] = {int(c["id"]): c for c in chips}
    start_ids = [int(c["id"]) for c in chips if int(c.get("input_id", -1)) == -1]
    if len(start_ids) != 1:
        raise ValueError(f"expected exactly one route source (input_id=-1), found {len(start_ids)}")

    route: List[int] = []
    seen = set()
    cur = start_ids[0]
    while cur != -1:
        if cur in seen:
            raise ValueError(f"cycle detected in routing while ordering chips: {cur}")
        if cur not in by_id:
            raise ValueError(f"route references unknown chip id: {cur}")
        seen.add(cur)
        route.append(cur)
        cur = int(by_id[cur].get("out_id", -1))

    if len(route) != len(chips):
        missing = sorted(set(by_id) - set(route))
        raise ValueError(f"route order does not cover all chips; missing={missing}")
    return route


def build_clock_wave(ticks: int) -> tuple[List[float], List[int]]:
    # 1 during first half of each tick, 0 during second half.
    x = [0.5 * i for i in range(2 * ticks + 1)]
    y: List[int] = []
    for i in range(2 * ticks):
        y.append(1 if (i % 2 == 0) else 0)
    y.append(0)
    return x, y


def build_tick_pulse(values: List[int]) -> tuple[List[int], List[int]]:
    # Hold each tick's pulse value across [tick, tick+1).
    x = list(range(len(values) + 1))
    y = values[:] + [0]
    return x, y


def parse_chip_list(chips_arg: str) -> List[int]:
    chips: List[int] = []
    for part in chips_arg.split(","):
        token = part.strip()
        if not token:
            continue
        chips.append(int(token))
    if not chips:
        raise ValueError("chip list is empty")
    if len(set(chips)) != len(chips):
        raise ValueError("chip list contains duplicates")
    return chips


def build_occupancy_percent_series(rows: List[tuple[int, int, int]], ticks: int, fifo_depth: int) -> List[float]:
    if fifo_depth <= 0:
        raise ValueError("fifo_depth must be > 0")
    per_tick_max_occ: Dict[int, int] = {}
    for tick, _ev, occ in rows:
        if 0 <= tick < ticks:
            prev = per_tick_max_occ.get(tick, 0)
            if occ > prev:
                per_tick_max_occ[tick] = occ
    out: List[float] = [0.0] * ticks
    last_occ = 0
    for tick in range(ticks):
        if tick in per_tick_max_occ:
            last_occ = per_tick_max_occ[tick]
        pct = (100.0 * float(last_occ)) / float(fifo_depth)
        out[tick] = max(0.0, min(100.0, pct))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="Plot clock and chip DEQ_OUT pulse waveforms")
    ap.add_argument("--run-dir", required=True, help="Trace run directory (contains manifest.json)")
    ap.add_argument("--out", required=True, help="Output PNG path")
    ap.add_argument(
        "--ticks",
        type=int,
        default=None,
        help="Optional tick limit for plotting (defaults to manifest ticks)",
    )
    ap.add_argument(
        "--chips",
        default=None,
        help="Optional comma-separated chip IDs to plot (defaults to all route chips)",
    )
    ap.add_argument(
        "--packet-out-only-chips",
        default=None,
        help="Optional comma-separated chip IDs to plot as PACKET_OUT-only lanes",
    )
    ap.add_argument(
        "--fifo-depth",
        type=int,
        default=64,
        help="FIFO depth used to convert occupancy to percentage (default: 64)",
    )
    ap.add_argument("--tick-min", type=int, default=None, help="Optional x-axis lower tick bound")
    ap.add_argument("--tick-max", type=int, default=None, help="Optional x-axis upper tick bound")
    args = ap.parse_args()

    run_dir = Path(args.run_dir)
    out_path = Path(args.out)

    manifest = load_manifest(run_dir)
    manifest_ticks = int(manifest.get("ticks", 0))
    ticks = manifest_ticks if args.ticks is None else int(args.ticks)
    chips = sorted(manifest.get("chips", []), key=lambda c: int(c["id"]))

    if manifest_ticks <= 0:
        raise ValueError("manifest ticks must be > 0")
    if ticks <= 0:
        raise ValueError("plot ticks must be > 0")
    if ticks > manifest_ticks:
        raise ValueError(f"plot ticks ({ticks}) exceed manifest ticks ({manifest_ticks})")
    if len(chips) == 0:
        raise ValueError("manifest contains no chips")
    if args.fifo_depth <= 0:
        raise ValueError("--fifo-depth must be > 0")

    tick_min = 0 if args.tick_min is None else int(args.tick_min)
    tick_max = ticks if args.tick_max is None else int(args.tick_max)
    if tick_min < 0 or tick_min > ticks:
        raise ValueError(f"--tick-min must be in [0, {ticks}]")
    if tick_max < 0 or tick_max > ticks:
        raise ValueError(f"--tick-max must be in [0, {ticks}]")
    if tick_max < tick_min:
        raise ValueError("--tick-max must be >= --tick-min")

    route_order = infer_route_order(chips)
    if args.chips is not None:
        selected = set(parse_chip_list(args.chips))
        known = set(route_order)
        unknown = sorted(selected - known)
        if unknown:
            raise ValueError(f"unknown chip ids requested: {unknown}")
        route_order = [chip_id for chip_id in route_order if chip_id in selected]
        if not route_order:
            raise ValueError("chip filter excluded all chips")

    packet_out_only: set[int] = set()
    if args.packet_out_only_chips is not None:
        packet_out_only = set(parse_chip_list(args.packet_out_only_chips))
        known = set(route_order)
        unknown = sorted(packet_out_only - known)
        if unknown:
            raise ValueError(f"unknown packet-out-only chip ids requested: {unknown}")
    deq_by_chip: Dict[int, List[int]] = {}
    gen_by_chip: Dict[int, List[int]] = {}
    enq_local_by_chip: Dict[int, List[int]] = {}
    enq_neigh_by_chip: Dict[int, List[int]] = {}
    occ_pct_by_chip: Dict[int, List[float]] = {}
    for chip in chips:
        chip_id = int(chip["id"])
        deq_vals = [0] * ticks
        gen_vals = [0] * ticks
        enq_local_vals = [0] * ticks
        enq_neigh_vals = [0] * ticks
        trace_path = run_dir / str(chip["file"])
        chip_rows = load_rows(trace_path)
        for tick, ev, _occ in chip_rows:
            if ev == EV_DEQ_OUT and 0 <= tick < ticks:
                deq_vals[tick] = 1
            if ev == EV_GEN_LOCAL and 0 <= tick < ticks:
                gen_vals[tick] = 1
            if ev == EV_ENQ_LOCAL_OK and 0 <= tick < ticks:
                enq_local_vals[tick] = 1
            if ev == EV_ENQ_NEIGH_OK and 0 <= tick < ticks:
                enq_neigh_vals[tick] = 1
        occ_pct_by_chip[chip_id] = build_occupancy_percent_series(chip_rows, ticks, args.fifo_depth)
        deq_by_chip[chip_id] = deq_vals
        gen_by_chip[chip_id] = gen_vals
        enq_local_by_chip[chip_id] = enq_local_vals
        enq_neigh_by_chip[chip_id] = enq_neigh_vals

    lane_count = len(route_order)
    trace_panels = [
        ("LOCAL_GENERATED", gen_by_chip, "#2ca02c", "-"),
        ("PASSTHRU_ENTER_FIFO", enq_neigh_by_chip, "#1f77b4", "--"),
        ("LOCAL_ENTER_FIFO", enq_local_by_chip, "#ff7f0e", "--"),
        ("PACKET_OUT", deq_by_chip, "#d62728", "-"),
    ]
    occ_panel = ("FIFO_OCCUPANCY_%", occ_pct_by_chip, "#111111", "-")
    packet_out_panel = trace_panels[-1]
    panels_per_chip: Dict[int, List[tuple[str, Dict[int, List[int]], str, str]]] = {}
    for chip_id in route_order:
        if chip_id in packet_out_only:
            panels_per_chip[chip_id] = [packet_out_panel]
        else:
            panels_per_chip[chip_id] = trace_panels + [occ_panel]
    subplot_count = 1 + sum(len(panels_per_chip[cid]) for cid in route_order)
    fig_height = max(2.0 * subplot_count, 6.0)
    fig, axes = plt.subplots(subplot_count, 1, figsize=(14, fig_height), sharex=True)
    if not isinstance(axes, (list, tuple)):
        axes = list(axes)

    clock_x, clock_y = build_clock_wave(ticks)
    axes[0].step(
        clock_x,
        clock_y,
        where="post",
        linewidth=TRACE_LINEWIDTH,
        label="CLOCK",
        color="#1f77b4",
    )
    axes[0].set_ylabel("CLOCK")
    axes[0].set_ylim(Y_MIN, Y_MAX)
    axes[0].set_yticks([])
    axes[0].tick_params(axis="y", left=False, labelleft=False)
    axes[0].legend(loc="upper right")
    axes[0].grid(True, alpha=0.25)

    ax_idx = 1
    for chip_id in route_order:
        for trace_name, data_by_chip, color, linestyle in panels_per_chip[chip_id]:
            ax = axes[ax_idx]
            ax_idx += 1
            tx, ty = build_tick_pulse(data_by_chip[chip_id])
            ax.step(
                tx,
                ty,
                where="post",
                linewidth=TRACE_LINEWIDTH,
                linestyle=linestyle,
                label=trace_name,
                color=color,
            )
            ax.set_ylabel(f"CHIP {chip_id}")
            if trace_name == "FIFO_OCCUPANCY_%":
                ax.set_ylim(0.0, 100.0)
                ax.set_yticks([0, 25, 50, 75, 100])
                ax.tick_params(axis="y", left=True, labelleft=True)
            else:
                ax.set_ylim(Y_MIN, Y_MAX)
                ax.set_yticks([])
                ax.tick_params(axis="y", left=False, labelleft=False)
            ax.legend(loc="upper right")
            ax.grid(True, alpha=0.25)

    axes[-1].set_xlabel("Ticks")
    axes[-1].set_xlim(tick_min, tick_max)
    axes[-1].set_xticks(list(range(tick_min, tick_max + 1)))

    fig.suptitle(f"Per-Chip FIFO/Traffic Waveforms (chips={lane_count})")
    fig.tight_layout()

    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, dpi=180)
    plt.close(fig)

    print(f"wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
