#!/usr/bin/env python3
"""Export per-tick FIFO contents for one chip trace as a text table."""

from __future__ import annotations

import argparse
import json
import struct
from collections import defaultdict, deque
from pathlib import Path
from typing import DefaultDict, Deque, Dict, List, Tuple

MAGIC = b"CTRACE01"
HEADER_SIZE = 64
ROW_SIZE = 24
ROW_STRUCT = struct.Struct("<QHHIQ")

EV_ENQ_LOCAL_OK = 2
EV_ENQ_NEIGH_OK = 4
EV_DEQ_OUT = 6


def load_manifest(run_dir: Path) -> dict:
    manifest_path = run_dir / "manifest.json"
    if not manifest_path.exists():
        raise FileNotFoundError(f"missing manifest: {manifest_path}")
    with manifest_path.open("r", encoding="utf-8") as f:
        return json.load(f)


def load_rows(trace_path: Path) -> List[Tuple[int, int, int]]:
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

    rows: List[Tuple[int, int, int]] = []
    for off in range(0, len(payload), ROW_SIZE):
        tick, event_type, _reserved0, _fifo_occupancy, packet_word = ROW_STRUCT.unpack_from(
            payload, off
        )
        rows.append((int(tick), int(event_type), int(packet_word)))
    return rows


def packet_word_to_str(word: int) -> str:
    return f"0x{word:016X}"


def format_row(values: List[str], widths: List[int]) -> str:
    return " | ".join(v.ljust(w) for v, w in zip(values, widths))


def format_md_row(values: List[str]) -> str:
    return "| " + " | ".join(values) + " |"


def build_md_run_header(
    run_dir: Path,
    manifest: dict,
    chip_id: int,
    fifo_depth: int,
    args: argparse.Namespace,
) -> List[str]:
    lines: List[str] = []
    chips = sorted(manifest.get("chips", []), key=lambda c: int(c["id"]))

    lines.append("# FIFO Contents Export")
    lines.append("")
    lines.append("## Run Summary")
    lines.append("")
    lines.append(f"- Run directory: `{run_dir}`")
    lines.append(f"- Manifest format: `{manifest.get('format', 'unknown')}`")
    lines.append(f"- Ticks: `{manifest.get('ticks', 'unknown')}`")
    lines.append(f"- FIFO depth used for table columns: `{fifo_depth}`")
    lines.append(f"- Selected chip for FIFO table: `{chip_id}`")
    lines.append(f"- Chip binary: `{manifest.get('chip_bin', 'unknown')}`")
    lines.append(f"- Table generator script: `scripts/export_fifo_contents.py`")
    lines.append(
        "- Table generator command: "
        f"`python3 scripts/export_fifo_contents.py --run-dir {run_dir} "
        f"--chip-id {args.chip_id} --fifo-depth {args.fifo_depth} --format {args.format}"
        + (" --include-io-cols" if args.include_io_cols else "")
        + f" --out {args.out}`"
    )
    lines.append("")
    lines.append("## Routing And Generation")
    lines.append("")
    lines.append("| chip_id | input_id | out_id | gen_ppm |")
    lines.append("| --- | --- | --- | --- |")
    for chip in chips:
        lines.append(
            f"| {int(chip['id'])} | {int(chip.get('input_id', -1))} | "
            f"{int(chip.get('out_id', -1))} | {int(chip.get('gen_ppm', -1))} |"
        )
    lines.append("")
    lines.append("## Per-Tick FIFO Table")
    lines.append("")
    return lines


def main() -> int:
    ap = argparse.ArgumentParser(description="Export per-tick FIFO content table for one chip")
    ap.add_argument("--run-dir", required=True, help="Trace run directory")
    ap.add_argument("--chip-id", required=True, type=int, help="Chip ID to inspect")
    ap.add_argument(
        "--fifo-depth",
        required=True,
        type=int,
        help="FIFO depth (number of slot columns to emit)",
    )
    ap.add_argument("--out", required=True, help="Output .txt file path")
    ap.add_argument(
        "--format",
        choices=("txt", "md"),
        default="txt",
        help="Output format: fixed-width text table (txt) or markdown table (md)",
    )
    ap.add_argument(
        "--include-io-cols",
        action="store_true",
        help="Include per-tick enter/exit packet columns (enter_local, enter_neigh, exit_out)",
    )
    args = ap.parse_args()

    if args.fifo_depth <= 0:
        raise ValueError("--fifo-depth must be > 0")
    if args.chip_id < 0:
        raise ValueError("--chip-id must be >= 0")

    run_dir = Path(args.run_dir)
    out_path = Path(args.out)
    manifest = load_manifest(run_dir)
    ticks = int(manifest.get("ticks", 0))
    if ticks <= 0:
        raise ValueError("manifest ticks must be > 0")

    chips = manifest.get("chips", [])
    chip_to_file: Dict[int, str] = {int(c["id"]): str(c["file"]) for c in chips}
    if args.chip_id not in chip_to_file:
        raise ValueError(f"chip id {args.chip_id} not found in manifest")

    trace_path = run_dir / chip_to_file[args.chip_id]
    rows = load_rows(trace_path)

    by_tick: DefaultDict[int, List[Tuple[int, int]]] = defaultdict(list)
    for tick, event_type, packet_word in rows:
        if 0 <= tick < ticks:
            by_tick[tick].append((event_type, packet_word))

    fifo: Deque[int] = deque()
    lines: List[str] = []
    if args.format == "md":
        lines.extend(build_md_run_header(run_dir, manifest, args.chip_id, args.fifo_depth, args))

    io_header = ["enter_local", "enter_neigh", "exit_out"] if args.include_io_cols else []
    header = ["tick"] + io_header + [f"slot_{i}" for i in range(args.fifo_depth)]
    tick_width = max(len("tick"), len(str(max(ticks - 1, 0))))
    slot_width = max(18, max(len(h) for h in header[1:]) if len(header) > 1 else 18)
    widths = [tick_width] + [slot_width] * (len(header) - 1)
    if args.format == "md":
        lines.append(format_md_row(header))
        lines.append(format_md_row(["---"] * len(header)))
    else:
        lines.append(format_row(header, widths))
        lines.append("-+-".join("-" * w for w in widths))

    for tick in range(ticks):
        events = by_tick.get(tick, [])
        enter_local = "-"
        enter_neigh = "-"
        exit_out = "-"

        # Dequeue event is emitted at tick start in current runtime model.
        deq_words = [word for ev, word in events if ev == EV_DEQ_OUT]
        deq_count = len(deq_words)
        if deq_words:
            exit_out = packet_word_to_str(deq_words[0])
        for _ in range(deq_count):
            if fifo:
                fifo.popleft()

        # Preserve fixed local-first arbitration semantics.
        for ev, word in events:
            if ev == EV_ENQ_LOCAL_OK:
                fifo.append(word)
                if enter_local == "-":
                    enter_local = packet_word_to_str(word)
        for ev, word in events:
            if ev == EV_ENQ_NEIGH_OK:
                fifo.append(word)
                if enter_neigh == "-":
                    enter_neigh = packet_word_to_str(word)

        slots = ["-"] * args.fifo_depth
        for i, word in enumerate(list(fifo)[: args.fifo_depth]):
            slots[i] = packet_word_to_str(word)
        row_vals = [str(tick)]
        if args.include_io_cols:
            row_vals.extend([enter_local, enter_neigh, exit_out])
        row_vals.extend(slots)
        if args.format == "md":
            lines.append(format_md_row(row_vals))
        else:
            lines.append(format_row(row_vals, widths))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
