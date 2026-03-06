#!/usr/bin/env python3
"""Run and report a 3x5 congestion-wave scenario (BR -> TL)."""

from __future__ import annotations

import argparse
import json
import re
import struct
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Tuple

try:
    import matplotlib.pyplot as plt
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "matplotlib is required for occupancy plotting. "
        "Install it (e.g. `pip install matplotlib`) and retry."
    ) from exc

MAGIC = b"CTRACE01"
HEADER_SIZE = 64
ROW_SIZE = 24
ROW_STRUCT = struct.Struct("<QHHIQ")

EV_GEN_LOCAL = 1
EV_ENQ_LOCAL_OK = 2
EV_ENQ_LOCAL_DROP_FULL = 3
EV_ENQ_NEIGH_OK = 4
EV_ENQ_NEIGH_DROP_FULL = 5
EV_DEQ_OUT = 6


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def dump_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def update_config(
    base_cfg: dict,
    gen_ppm: int,
    fifo_depth: int,
    ticks: int,
    chip_bin: str | None,
    trace_dir: Path,
    trace_run_id: str,
) -> dict:
    cfg = json.loads(json.dumps(base_cfg))

    runtime = cfg.setdefault("runtime", {})
    runtime["fifo_depth"] = int(fifo_depth)
    runtime["ticks"] = int(ticks)
    runtime["trace_dir"] = str(trace_dir)
    runtime["trace_run_id"] = trace_run_id
    if chip_bin:
        runtime["chip_bin"] = chip_bin

    traffic = cfg.setdefault("traffic", {})
    traffic["gen_ppm"] = int(gen_ppm)

    routes = cfg.get("routes", [])
    if not isinstance(routes, list) or not routes:
        raise ValueError("config must define non-empty routes[] for explicit BR->TL mapping")

    for route in routes:
        if not isinstance(route, dict) or "id" not in route:
            raise ValueError("each routes[] entry must include id")
        route["gen_ppm"] = int(gen_ppm)

    return cfg


def parse_run_log(log_path: Path) -> Tuple[dict, Path]:
    text = log_path.read_text(encoding="utf-8")

    metrics_match = re.findall(
        r"^metrics: tx=(\d+) rx=(\d+) local=(\d+) drops=(\d+) fifo_peak=(\d+)\s*$",
        text,
        flags=re.MULTILINE,
    )
    benchmark_match = re.findall(
        r"^benchmark: ticks=(\d+) cycles_per_sec=([0-9.]+)\s+.*$",
        text,
        flags=re.MULTILINE,
    )
    trace_match = re.findall(
        r"^orchestrator: trace_run_id=([^\s]+) trace_dir=([^\s]+)\s*$",
        text,
        flags=re.MULTILINE,
    )

    if not metrics_match:
        raise RuntimeError(f"missing metrics line in log: {log_path}")
    if not benchmark_match:
        raise RuntimeError(f"missing benchmark line in log: {log_path}")
    if not trace_match:
        raise RuntimeError(f"missing trace directory line in log: {log_path}")

    tx, rx, local, drops, fifo_peak = metrics_match[-1]
    ticks, cycles_per_sec = benchmark_match[-1]
    _trace_run_id, trace_dir = trace_match[-1]

    parsed = {
        "tx": int(tx),
        "rx": int(rx),
        "local": int(local),
        "drops": int(drops),
        "fifo_peak": int(fifo_peak),
        "ticks": int(ticks),
        "cycles_per_sec": float(cycles_per_sec),
    }
    return parsed, Path(trace_dir)


def load_trace_rows(trace_path: Path) -> List[Tuple[int, int, int]]:
    data = trace_path.read_bytes()
    if len(data) < HEADER_SIZE:
        raise ValueError(f"trace file too short: {trace_path}")

    magic = data[:8]
    if magic != MAGIC:
        raise ValueError(f"bad trace magic in {trace_path}")

    header_size = int.from_bytes(data[14:16], "little")
    record_size = int.from_bytes(data[16:18], "little")
    if header_size != HEADER_SIZE or record_size != ROW_SIZE:
        raise ValueError(
            f"unsupported trace row/header size in {trace_path}: {header_size}/{record_size}"
        )

    payload = data[HEADER_SIZE:]
    if len(payload) % ROW_SIZE != 0:
        raise ValueError(f"corrupt trace row alignment in {trace_path}")

    rows: List[Tuple[int, int, int]] = []
    for off in range(0, len(payload), ROW_SIZE):
        tick, event_type, _reserved0, fifo_occupancy, _packet_word = ROW_STRUCT.unpack_from(
            payload, off
        )
        rows.append((int(tick), int(event_type), int(fifo_occupancy)))
    return rows


def analyze_trace_run(trace_run_dir: Path) -> dict:
    manifest_path = trace_run_dir / "manifest.json"
    if not manifest_path.exists():
        raise FileNotFoundError(f"missing manifest: {manifest_path}")

    manifest = load_json(manifest_path)
    chips = sorted(manifest.get("chips", []), key=lambda c: int(c["id"]))
    ticks = int(manifest.get("ticks", 0))
    if ticks <= 0:
        raise ValueError("manifest ticks must be > 0")

    per_chip: Dict[int, dict] = {}
    occupancy_by_chip: Dict[int, List[int]] = {}

    for chip in chips:
        chip_id = int(chip["id"])
        trace_file = trace_run_dir / str(chip["file"])
        rows = load_trace_rows(trace_file)

        counts = {
            "generated": 0,
            "enq_local_ok": 0,
            "enq_neigh_ok": 0,
            "local_drops": 0,
            "passthrough_drops": 0,
            "forwarded": 0,
        }
        last_occ_by_tick: Dict[int, int] = {}

        for tick, event_type, occ in rows:
            last_occ_by_tick[tick] = occ

            if event_type == EV_GEN_LOCAL:
                counts["generated"] += 1
            elif event_type == EV_ENQ_LOCAL_OK:
                counts["enq_local_ok"] += 1
            elif event_type == EV_ENQ_LOCAL_DROP_FULL:
                counts["local_drops"] += 1
            elif event_type == EV_ENQ_NEIGH_OK:
                counts["enq_neigh_ok"] += 1
            elif event_type == EV_ENQ_NEIGH_DROP_FULL:
                counts["passthrough_drops"] += 1
            elif event_type == EV_DEQ_OUT:
                counts["forwarded"] += 1

        occupancy_series = [0] * ticks
        occ = 0
        for tick in range(ticks):
            if tick in last_occ_by_tick:
                occ = last_occ_by_tick[tick]
            occupancy_series[tick] = occ

        counts["total_drops"] = counts["local_drops"] + counts["passthrough_drops"]
        counts["fifo_peak_observed"] = max(occupancy_series) if occupancy_series else 0

        per_chip[chip_id] = counts
        occupancy_by_chip[chip_id] = occupancy_series

    return {
        "manifest": manifest,
        "per_chip": per_chip,
        "occupancy_by_chip": occupancy_by_chip,
    }


def write_per_chip_tsv(path: Path, per_chip: Dict[int, dict]) -> None:
    headers = [
        "chip_id",
        "generated",
        "forwarded",
        "local_drops",
        "passthrough_drops",
        "total_drops",
        "enq_local_ok",
        "enq_neigh_ok",
        "fifo_peak_observed",
    ]

    lines = ["\t".join(headers)]
    for chip_id in sorted(per_chip):
        c = per_chip[chip_id]
        lines.append(
            "\t".join(
                [
                    str(chip_id),
                    str(c["generated"]),
                    str(c["forwarded"]),
                    str(c["local_drops"]),
                    str(c["passthrough_drops"]),
                    str(c["total_drops"]),
                    str(c["enq_local_ok"]),
                    str(c["enq_neigh_ok"]),
                    str(c["fifo_peak_observed"]),
                ]
            )
        )

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_occupancy_tsv(path: Path, occupancy_by_chip: Dict[int, List[int]]) -> None:
    chip_ids = sorted(occupancy_by_chip)
    if not chip_ids:
        raise ValueError("no chip occupancy series to write")

    ticks = len(occupancy_by_chip[chip_ids[0]])
    headers = ["tick"] + [f"chip_{cid}" for cid in chip_ids]
    lines = ["\t".join(headers)]

    for tick in range(ticks):
        row = [str(tick)]
        for cid in chip_ids:
            row.append(str(occupancy_by_chip[cid][tick]))
        lines.append("\t".join(row))

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def plot_occupancy_grouped(
    out_dir: Path, occupancy_by_chip: Dict[int, List[int]], fifo_depth: int
) -> List[Path]:
    chip_ids = sorted(occupancy_by_chip)
    if not chip_ids:
        raise ValueError("no chip occupancy data available for plotting")

    ticks = len(occupancy_by_chip[chip_ids[0]])
    x = list(range(ticks))

    groups = [(0, 4), (5, 9), (10, 14)]
    out_paths: List[Path] = []
    out_dir.mkdir(parents=True, exist_ok=True)

    for start, end in groups:
        selected = [cid for cid in chip_ids if start <= cid <= end]
        if not selected:
            continue

        fig, ax = plt.subplots(figsize=(13, 6.5))
        for cid in selected:
            ax.plot(x, occupancy_by_chip[cid], linewidth=1.0, label=f"chip_{cid}")

        ax.set_xlabel("Ticks")
        ax.set_ylabel("FIFO Occupancy")
        ax.set_title(f"3x5 BR->TL Congestion Wave: FIFO Occupancy (chips {start}-{end})")
        ax.set_ylim(0, max(fifo_depth, 1))
        ax.grid(True, alpha=0.3)
        ax.legend(loc="upper right", ncol=1, fontsize=9, frameon=False)

        out_path = out_dir / f"fifo_occupancy_chips_{start}_{end}.png"
        fig.tight_layout()
        fig.savefig(out_path, dpi=160)
        plt.close(fig)
        out_paths.append(out_path)

    return out_paths


def write_report(
    path: Path,
    config_path: Path,
    run_log_path: Path,
    trace_run_dir: Path,
    plot_paths: List[Path],
    per_chip_tsv: Path,
    occupancy_tsv: Path,
    run_metrics: dict,
    per_chip: Dict[int, dict],
) -> None:
    total_generated = sum(v["generated"] for v in per_chip.values())
    total_forwarded = sum(v["forwarded"] for v in per_chip.values())
    total_local_drops = sum(v["local_drops"] for v in per_chip.values())
    total_passthrough_drops = sum(v["passthrough_drops"] for v in per_chip.values())
    total_drops = sum(v["total_drops"] for v in per_chip.values())

    lines: List[str] = []
    lines.append("# 3x5 Congestion-Wave Report (Bottom-Right -> Top-Left)")
    lines.append("")
    lines.append("## Run Setup")
    lines.append("")
    lines.append(f"- Effective config: `{config_path}`")
    lines.append(f"- Run log: `{run_log_path}`")
    lines.append(f"- Trace run dir: `{trace_run_dir}`")
    lines.append("")
    lines.append("## Aggregate Results")
    lines.append("")
    lines.append(f"- Generated packets (trace `GEN_LOCAL`): {total_generated}")
    lines.append(f"- Forwarded packets (trace `DEQ_OUT`): {total_forwarded}")
    lines.append(f"- Local drops (`ENQ_LOCAL_DROP_FULL`): {total_local_drops}")
    lines.append(f"- Pass-through drops (`ENQ_NEIGH_DROP_FULL`): {total_passthrough_drops}")
    lines.append(f"- Total drops (trace): {total_drops}")
    lines.append(f"- Total drops (orchestrator metrics): {run_metrics['drops']}")
    lines.append(f"- Delivered tx (orchestrator metrics): {run_metrics['tx']}")
    lines.append(f"- Cycles/sec (orchestrator benchmark): {run_metrics['cycles_per_sec']:.3f}")
    lines.append("")
    lines.append("## Per-Chip Metrics")
    lines.append("")
    lines.append("| Chip | Generated | Forwarded | Local Drops | Pass-through Drops | Total Drops | FIFO Peak |")
    lines.append("| ---: | ---: | ---: | ---: | ---: | ---: | ---: |")

    for chip_id in sorted(per_chip):
        c = per_chip[chip_id]
        lines.append(
            "| {chip} | {gen} | {fwd} | {ld} | {pd} | {td} | {peak} |".format(
                chip=chip_id,
                gen=c["generated"],
                fwd=c["forwarded"],
                ld=c["local_drops"],
                pd=c["passthrough_drops"],
                td=c["total_drops"],
                peak=c["fifo_peak_observed"],
            )
        )

    lines.append("")
    lines.append("## FIFO Occupancy Over Time")
    lines.append("")
    lines.append("The plots below show FIFO occupancy vs tick, grouped as 5 chips per axis.")
    lines.append("")
    for plot_path in plot_paths:
        lines.append(f"### `{plot_path.stem}`")
        lines.append("")
        lines.append(f"![{plot_path.stem}]({plot_path.name})")
        lines.append("")
    lines.append("")
    lines.append("## Data Files")
    lines.append("")
    lines.append(f"- Per-chip metrics TSV: `{per_chip_tsv}`")
    lines.append(f"- Occupancy timeseries TSV: `{occupancy_tsv}`")

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    root_dir = Path(__file__).resolve().parents[1]

    ap = argparse.ArgumentParser(description="Run 3x5 congestion-wave test and write report")
    ap.add_argument(
        "--config-template",
        default=str(root_dir / "config" / "network_3x5_congestion_wave_br_to_tl.json"),
        help="Base config template path",
    )
    ap.add_argument("--gen-ppm", type=int, default=25000, help="Per-chip generation rate (ppm)")
    ap.add_argument("--fifo-depth", type=int, default=64, help="FIFO depth for all chips")
    ap.add_argument("--ticks", type=int, default=50000, help="Simulation tick count")
    ap.add_argument("--chip-bin", default=None, help="Optional chip binary override")
    ap.add_argument(
        "--out-dir",
        default=None,
        help="Optional output report directory (default: reports/congestion_wave_3x5/<timestamp>)",
    )
    args = ap.parse_args()

    if not (0 <= args.gen_ppm <= 1_000_000):
        raise SystemExit("--gen-ppm must be in [0, 1000000]")
    if args.fifo_depth <= 0:
        raise SystemExit("--fifo-depth must be > 0")
    if args.ticks <= 0:
        raise SystemExit("--ticks must be > 0")

    orchestrator_bin = root_dir / "build" / "orchestrator"
    if not orchestrator_bin.exists():
        raise SystemExit(
            f"missing executable: {orchestrator_bin}\\n"
            "build first: cmake -S . -B build && cmake --build build -j"
        )

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = Path(args.out_dir) if args.out_dir else (root_dir / "reports" / "congestion_wave_3x5" / stamp)
    out_dir.mkdir(parents=True, exist_ok=True)

    trace_root = out_dir / "traces"
    trace_run_id = f"congestion_wave_3x5_{stamp}"

    cfg_template_path = Path(args.config_template)
    if not cfg_template_path.exists():
        raise SystemExit(f"config template not found: {cfg_template_path}")

    base_cfg = load_json(cfg_template_path)
    eff_cfg = update_config(
        base_cfg=base_cfg,
        gen_ppm=args.gen_ppm,
        fifo_depth=args.fifo_depth,
        ticks=args.ticks,
        chip_bin=args.chip_bin,
        trace_dir=trace_root,
        trace_run_id=trace_run_id,
    )

    eff_cfg_path = out_dir / "effective_config.json"
    dump_json(eff_cfg_path, eff_cfg)

    run_log_path = out_dir / "run.log"
    run_cmd = [
        "python3",
        str(root_dir / "scripts" / "run_from_config.py"),
        "-cfg",
        str(eff_cfg_path),
    ]

    with run_log_path.open("w", encoding="utf-8") as logf:
        proc = subprocess.run(run_cmd, cwd=root_dir, stdout=logf, stderr=subprocess.STDOUT)
    if proc.returncode != 0:
        raise SystemExit(f"simulation failed (exit={proc.returncode}); see {run_log_path}")

    run_metrics, trace_run_dir = parse_run_log(run_log_path)
    analysis = analyze_trace_run(trace_run_dir)
    per_chip = analysis["per_chip"]
    occupancy_by_chip = analysis["occupancy_by_chip"]

    total_drops_trace = sum(v["total_drops"] for v in per_chip.values())
    if total_drops_trace != run_metrics["drops"]:
        raise SystemExit(
            "drop-count mismatch between trace and orchestrator metrics: "
            f"trace={total_drops_trace}, metrics={run_metrics['drops']}"
        )

    per_chip_tsv = out_dir / "per_chip_metrics.tsv"
    occupancy_tsv = out_dir / "fifo_occupancy_timeseries.tsv"
    plot_paths = plot_occupancy_grouped(out_dir, occupancy_by_chip, args.fifo_depth)
    if len(plot_paths) != 3:
        raise SystemExit(f"expected 3 occupancy plots, found {len(plot_paths)}")
    report_md = out_dir / "congestion_wave_report.md"

    write_per_chip_tsv(per_chip_tsv, per_chip)
    write_occupancy_tsv(occupancy_tsv, occupancy_by_chip)
    write_report(
        report_md,
        eff_cfg_path,
        run_log_path,
        trace_run_dir,
        plot_paths,
        per_chip_tsv,
        occupancy_tsv,
        run_metrics,
        per_chip,
    )

    print("done")
    print(f"output_dir={out_dir}")
    print(f"report={report_md}")
    for plot_path in plot_paths:
        print(f"plot={plot_path}")
    print(f"per_chip_metrics={per_chip_tsv}")
    print(f"occupancy_tsv={occupancy_tsv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
