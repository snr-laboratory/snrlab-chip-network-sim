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
        tick, ev, _r0, _occ, _word = ROW_STRUCT.unpack_from(payload, off)
        rows.append((int(tick), int(ev), 0))
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
    deq_by_chip: Dict[int, List[int]] = {}
    gen_by_chip: Dict[int, List[int]] = {}
    enq_local_by_chip: Dict[int, List[int]] = {}
    enq_neigh_by_chip: Dict[int, List[int]] = {}
    for chip in chips:
        chip_id = int(chip["id"])
        deq_vals = [0] * ticks
        gen_vals = [0] * ticks
        enq_local_vals = [0] * ticks
        enq_neigh_vals = [0] * ticks
        trace_path = run_dir / str(chip["file"])
        for tick, ev, _ in load_rows(trace_path):
            if ev == EV_DEQ_OUT and 0 <= tick < ticks:
                deq_vals[tick] = 1
            if ev == EV_GEN_LOCAL and 0 <= tick < ticks:
                gen_vals[tick] = 1
            if ev == EV_ENQ_LOCAL_OK and 0 <= tick < ticks:
                enq_local_vals[tick] = 1
            if ev == EV_ENQ_NEIGH_OK and 0 <= tick < ticks:
                enq_neigh_vals[tick] = 1
        deq_by_chip[chip_id] = deq_vals
        gen_by_chip[chip_id] = gen_vals
        enq_local_by_chip[chip_id] = enq_local_vals
        enq_neigh_by_chip[chip_id] = enq_neigh_vals

    lane_count = len(route_order)
    fig_height = max(4.0 + 1.4 * lane_count, 6.0)
    fig, axes = plt.subplots(lane_count + 1, 1, figsize=(14, fig_height), sharex=True)
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

    for i, chip_id in enumerate(route_order, start=1):
        nx, ny = build_tick_pulse(enq_neigh_by_chip[chip_id])
        axes[i].step(
            nx,
            ny,
            where="post",
            linewidth=TRACE_LINEWIDTH,
            linestyle="--",
            label="PASSTHRU_ENTER_FIFO",
            color="#1f77b4",
        )
        lx, ly = build_tick_pulse(enq_local_by_chip[chip_id])
        axes[i].step(
            lx,
            ly,
            where="post",
            linewidth=TRACE_LINEWIDTH,
            linestyle="--",
            label="LOCAL_ENTER_FIFO",
            color="#ff7f0e",
        )

        sx, sy = build_tick_pulse(deq_by_chip[chip_id])
        axes[i].step(
            sx,
            sy,
            where="post",
            linewidth=TRACE_LINEWIDTH,
            label="PACKET_OUT",
            color="#d62728",
        )

        if any(gen_by_chip[chip_id]):
            gx, gy = build_tick_pulse(gen_by_chip[chip_id])
            axes[i].step(
                gx,
                gy,
                where="post",
                linewidth=TRACE_LINEWIDTH,
                label="LOCAL_GENERATED",
                color="#2ca02c",
            )
        axes[i].set_ylabel(f"CHIP {chip_id}")
        axes[i].set_ylim(Y_MIN, Y_MAX)
        axes[i].set_yticks([])
        axes[i].tick_params(axis="y", left=False, labelleft=False)
        axes[i].legend(loc="upper right")
        axes[i].grid(True, alpha=0.25)

    axes[-1].set_xlabel("Ticks")
    axes[-1].set_xlim(0, ticks)
    axes[-1].set_xticks(list(range(0, ticks + 1)))

    fig.suptitle(f"Clock and Per-Chip Packet-Exit Pulses (chips={lane_count})")
    fig.tight_layout()

    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, dpi=180)
    plt.close(fig)

    print(f"wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
