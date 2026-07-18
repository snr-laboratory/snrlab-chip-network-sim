#!/usr/bin/env python3
"""Plot selected shared-FIFO occupancies from the 15x15 two-track run."""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.ticker import MaxNLocator


DEFAULT_CHIPS = (3, 6, 10, 145, 64, 96)


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[2]
    run_dir = repo_root / "build" / "larpix_15x15_event_staggered_multichip__v3c"
    parser = argparse.ArgumentParser(
        description="Plot shared-FIFO occupancy for selected chips in the 15x15 two-track scenario"
    )
    parser.add_argument("--trace", type=Path, default=run_dir / "trace.jsonl")
    parser.add_argument(
        "--out",
        type=Path,
        default=run_dir / "visualization" / "selected_chip_fifo_occupancy_ticks_1000_18000.png",
    )
    parser.add_argument("--start-tick", type=int, default=1000)
    parser.add_argument("--end-tick", type=int, default=18000)
    parser.add_argument("--chips", type=int, nargs="+", default=DEFAULT_CHIPS)
    return parser.parse_args()


def load_updates(trace_path: Path, selected: set[int]) -> dict[int, list[tuple[int, int]]]:
    updates: dict[int, list[tuple[int, int]]] = defaultdict(list)
    with trace_path.open() as trace_file:
        for line_number, line in enumerate(trace_file, start=1):
            try:
                event = json.loads(line)
            except json.JSONDecodeError as error:
                raise ValueError(f"{trace_path}:{line_number}: invalid JSON: {error}") from error
            runtime_id = int(event.get("runtime_id", -1))
            if event.get("event") != "shared_fifo_occupancy" or runtime_id not in selected:
                continue
            updates[runtime_id].append(
                (int(event.get("seq", 0)), int(event.get("value_u32", 0)))
            )
    for entries in updates.values():
        entries.sort()
    return updates


def step_series(
    updates: list[tuple[int, int]], start_tick: int, end_tick: int
) -> tuple[list[int], list[int]]:
    value_at_start = 0
    for tick, value in updates:
        if tick > start_tick:
            break
        value_at_start = value

    ticks = [start_tick]
    values = [value_at_start]
    for tick, value in updates:
        if start_tick < tick <= end_tick:
            ticks.append(tick)
            values.append(value)
    ticks.append(end_tick)
    values.append(values[-1])
    return ticks, values


def main() -> int:
    args = parse_args()
    if args.start_tick >= args.end_tick:
        raise SystemExit("--start-tick must be less than --end-tick")
    if not args.trace.is_file():
        raise SystemExit(f"trace file does not exist: {args.trace}")

    chips = sorted(set(args.chips))
    updates = load_updates(args.trace, set(chips))
    missing = [chip for chip in chips if chip not in updates]
    if missing:
        raise SystemExit(f"no FIFO occupancy events found for chip IDs: {missing}")

    colors = ("#0B6E75", "#D1495B", "#EDA33B", "#6B5CA5", "#247BA0", "#708B36")
    fig, ax = plt.subplots(figsize=(14, 7.5), constrained_layout=True)
    fig.patch.set_facecolor("#F3F0E8")
    ax.set_facecolor("#FBFAF6")

    for index, chip_id in enumerate(chips):
        ticks, values = step_series(updates[chip_id], args.start_tick, args.end_tick)
        ax.step(
            ticks,
            values,
            where="post",
            linewidth=1.8,
            color=colors[index % len(colors)],
            label=f"Chip {chip_id}",
        )

    ax.set_xlim(args.start_tick, args.end_tick)
    ax.set_ylim(bottom=0)
    ax.set_xlabel("Simulation Tick", fontsize=12)
    ax.set_ylabel("Shared FIFO Occupancy (packets)", fontsize=12)
    ax.set_title(
        "15x15 v3c Two-Track Scenario: Selected Chip FIFO Occupancy",
        fontsize=16,
        fontweight="bold",
        loc="center",
    )
    ax.yaxis.set_major_locator(MaxNLocator(integer=True))
    ax.grid(axis="both", color="#D8D3C7", linewidth=0.8, alpha=0.75)
    ax.spines[["top", "right"]].set_visible(False)
    ax.legend(ncols=1, frameon=False, loc="upper left", bbox_to_anchor=(1.01, 1.0))

    args.out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.out, dpi=180)
    plt.close(fig)
    print(args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
