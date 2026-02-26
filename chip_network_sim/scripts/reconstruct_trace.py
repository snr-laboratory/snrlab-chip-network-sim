#!/usr/bin/env python3
"""Reconstruct minimal packet trace timelines from binary per-chip logs."""

from __future__ import annotations

import argparse
import json
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List

MAGIC = b"CTRACE01"
HEADER_SIZE = 64
ROW_SIZE = 24
ROW_STRUCT = struct.Struct("<QHHIQ")

EVENT_NAMES = {
    1: "GEN_LOCAL",
    2: "ENQ_LOCAL_OK",
    3: "ENQ_LOCAL_DROP_FULL",
    4: "ENQ_NEIGH_OK",
    5: "ENQ_NEIGH_DROP_FULL",
    6: "DEQ_OUT",
}

EVENT_TOKENS = {
    1: "G",   # generated local packet
    2: "IL",  # entered FIFO (local)
    3: "XL",  # dropped on local enqueue
    4: "IN",  # entered FIFO (neighbor)
    5: "XN",  # dropped on neighbor enqueue
    6: "O",   # left FIFO / output event
}


@dataclass
class TraceRow:
    tick: int
    event_type: int
    fifo_occupancy: int
    packet_word: int
    chip_id: int
    local_index: int


def load_manifest(run_dir: Path) -> dict:
    p = run_dir / "manifest.json"
    if not p.exists():
        raise FileNotFoundError(f"missing manifest: {p}")
    with p.open("r", encoding="utf-8") as f:
        return json.load(f)


def load_trace_file(path: Path) -> List[TraceRow]:
    data = path.read_bytes()
    if len(data) < HEADER_SIZE:
        raise ValueError(f"trace too short: {path}")

    magic = data[:8]
    chip_id = int.from_bytes(data[8:12], "little")
    version = int.from_bytes(data[12:14], "little")
    header_size = int.from_bytes(data[14:16], "little")
    record_size = int.from_bytes(data[16:18], "little")

    if magic != MAGIC:
        raise ValueError(f"bad magic in {path}: {magic!r}")
    if version != 1:
        raise ValueError(f"unsupported trace version in {path}: {version}")
    if header_size != HEADER_SIZE or record_size != ROW_SIZE:
        raise ValueError(
            f"bad sizes in {path}: header_size={header_size} record_size={record_size}"
        )

    payload = data[HEADER_SIZE:]
    if len(payload) % ROW_SIZE != 0:
        raise ValueError(f"corrupt row alignment in {path}")

    rows: List[TraceRow] = []
    for idx in range(len(payload) // ROW_SIZE):
        tick, event_type, _reserved0, fifo_occupancy, packet_word = ROW_STRUCT.unpack_from(
            payload, idx * ROW_SIZE
        )
        rows.append(
            TraceRow(
                tick=tick,
                event_type=event_type,
                fifo_occupancy=fifo_occupancy,
                packet_word=packet_word,
                chip_id=chip_id,
                local_index=idx,
            )
        )
    return rows


def summarize(rows: List[TraceRow]) -> dict:
    by_packet: Dict[int, dict] = {}
    event_totals: Dict[str, int] = {}

    for row in rows:
        ename = EVENT_NAMES.get(row.event_type, f"UNKNOWN_{row.event_type}")
        event_totals[ename] = event_totals.get(ename, 0) + 1

        p = by_packet.setdefault(
            row.packet_word,
            {
                "packet_word": row.packet_word,
                "first_tick": row.tick,
                "last_tick": row.tick,
                "first_chip": row.chip_id,
                "last_chip": row.chip_id,
                "event_count": 0,
                "deq_count": 0,
                "drop_count": 0,
            },
        )
        p["first_tick"] = min(p["first_tick"], row.tick)
        p["last_tick"] = max(p["last_tick"], row.tick)
        if row.tick <= p["first_tick"]:
            p["first_chip"] = row.chip_id
        if row.tick >= p["last_tick"]:
            p["last_chip"] = row.chip_id
        p["event_count"] += 1
        if row.event_type == 6:
            p["deq_count"] += 1
        if row.event_type in (3, 5):
            p["drop_count"] += 1

    packets = list(by_packet.values())
    packets.sort(key=lambda x: (x["first_tick"], x["packet_word"]))

    return {
        "trace_rows": len(rows),
        "unique_packets": len(packets),
        "event_totals": event_totals,
        "packets": packets,
    }


def parse_packet_words(spec: str) -> List[int]:
    out: List[int] = []
    if not spec:
        return out
    for raw in spec.split(","):
        item = raw.strip()
        if not item:
            continue
        out.append(int(item, 0))
    return out


def fit_cell(text: str, width: int) -> str:
    if width <= 0:
        return ""
    if len(text) <= width:
        return text.ljust(width)
    if width <= 3:
        return text[:width]
    return text[: width - 3] + "..."


def event_token(row: TraceRow) -> str:
    tok = EVENT_TOKENS.get(row.event_type, "?")
    return f"{tok}@{row.chip_id}"


def build_ascii_packet_history(
    rows: List[TraceRow],
    packet_words: List[int],
    cell_width: int,
    tick_min: int,
    tick_max: int,
) -> str:
    row_by_packet: Dict[int, List[TraceRow]] = {}
    for row in rows:
        row_by_packet.setdefault(row.packet_word, []).append(row)

    selected = packet_words[:]
    if not selected:
        return "No packets selected.\n"

    existing = [pw for pw in selected if pw in row_by_packet]
    missing = [pw for pw in selected if pw not in row_by_packet]

    if not existing:
        return "None of the selected packets were found in this run.\n"

    timelines: Dict[int, Dict[int, List[str]]] = {}
    for pw in existing:
        tick_map: Dict[int, List[str]] = {}
        for row in sorted(row_by_packet[pw], key=lambda r: (r.tick, r.chip_id, r.local_index)):
            tick_map.setdefault(row.tick, []).append(event_token(row))
        timelines[pw] = tick_map

    tick_w = max(4, len(str(tick_max)))
    headers = [fit_cell(f"0x{pw:016x}", cell_width) for pw in existing]

    lines: List[str] = []
    lines.append("Packet Lifetime History")
    lines.append(
        "Legend: G=generated, IL/IN=entered FIFO(local/neigh), O=left FIFO, "
        "XL/XN=dropped(local/neigh); @<chip_id>"
    )
    lines.append(f"Tick range: {tick_min}..{tick_max}")
    if missing:
        lines.append(
            "Missing packets: " + ", ".join(f"0x{pw:016x}" for pw in missing)
        )
    lines.append("")

    head = f"{'tick':>{tick_w}} | " + " | ".join(headers)
    sep = "-" * len(head)
    lines.append(head)
    lines.append(sep)

    for tick in range(tick_min, tick_max + 1):
        cells: List[str] = []
        for pw in existing:
            events = timelines[pw].get(tick)
            if not events:
                text = "."
            else:
                text = ",".join(events)
            cells.append(fit_cell(text, cell_width))
        lines.append(f"{tick:>{tick_w}} | " + " | ".join(cells))

    return "\n".join(lines) + "\n"


def select_plot_packets(summary: dict, explicit: List[int], plot_top: int) -> List[int]:
    selected: List[int] = []
    seen = set()

    for pw in explicit:
        if pw not in seen:
            selected.append(pw)
            seen.add(pw)

    if plot_top > 0:
        for pkt in summary["packets"]:
            pw = int(pkt["packet_word"])
            if pw in seen:
                continue
            selected.append(pw)
            seen.add(pw)
            if len(selected) >= len(explicit) + plot_top:
                break

    if not selected:
        for pkt in summary["packets"][:4]:
            pw = int(pkt["packet_word"])
            selected.append(pw)

    return selected


def main() -> int:
    ap = argparse.ArgumentParser(description="Reconstruct packet timelines from tracebin logs")
    ap.add_argument("-run", "--run-dir", required=True, help="Trace run directory")
    ap.add_argument("--top", type=int, default=20, help="Show top-N packets in summary")
    ap.add_argument("--json-out", help="Optional path to write full JSON summary")
    ap.add_argument(
        "--plot-out",
        help="Optional output ASCII file path for packet lifetime history plot",
    )
    ap.add_argument(
        "--plot-packets",
        default="",
        help="Comma-separated packet words (hex or int), e.g. 0x00000000096002cb,0x123",
    )
    ap.add_argument(
        "--plot-top",
        type=int,
        default=0,
        help="Also include first N packets by earliest appearance in plot columns",
    )
    ap.add_argument(
        "--plot-cell-width",
        type=int,
        default=22,
        help="ASCII plot column width per packet",
    )
    ap.add_argument(
        "--plot-compact-range",
        action="store_true",
        help="Use compact tick range covering only selected packet activity",
    )
    ap.add_argument(
        "--plot-tick-min",
        type=int,
        default=None,
        help="Override plot tick lower bound (inclusive)",
    )
    ap.add_argument(
        "--plot-tick-max",
        type=int,
        default=None,
        help="Override plot tick upper bound (inclusive)",
    )
    args = ap.parse_args()

    run_dir = Path(args.run_dir)
    manifest = load_manifest(run_dir)

    rows: List[TraceRow] = []
    for chip in manifest.get("chips", []):
        file_name = chip.get("file")
        if not file_name:
            continue
        rows.extend(load_trace_file(run_dir / file_name))

    rows.sort(key=lambda r: (r.tick, r.chip_id, r.local_index))
    summary = summarize(rows)

    print(f"run_id={manifest.get('run_id', '<unknown>')}")
    print(f"rows={summary['trace_rows']} unique_packets={summary['unique_packets']}")
    print("event_totals:")
    for name in sorted(summary["event_totals"]):
        print(f"  {name}: {summary['event_totals'][name]}")

    print(f"top_packets (first {max(args.top, 0)}):")
    for pkt in summary["packets"][: max(args.top, 0)]:
        print(
            "  packet=0x{pw:016x} first_tick={ft} last_tick={lt} "
            "first_chip={fc} last_chip={lc} deq={dq} drops={dr}".format(
                pw=pkt["packet_word"],
                ft=pkt["first_tick"],
                lt=pkt["last_tick"],
                fc=pkt["first_chip"],
                lc=pkt["last_chip"],
                dq=pkt["deq_count"],
                dr=pkt["drop_count"],
            )
        )

    if args.json_out:
        out_path = Path(args.json_out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with out_path.open("w", encoding="utf-8") as f:
            json.dump({"manifest": manifest, "summary": summary}, f, indent=2)
        print(f"wrote {out_path}")

    if args.plot_out:
        explicit = parse_packet_words(args.plot_packets)
        selected = select_plot_packets(summary, explicit, max(args.plot_top, 0))
        selected_rows = [r for r in rows if r.packet_word in set(selected)]

        if args.plot_tick_min is not None:
            tick_min = args.plot_tick_min
        elif args.plot_compact_range and selected_rows:
            tick_min = int(min(r.tick for r in selected_rows))
        else:
            tick_min = 0

        if args.plot_tick_max is not None:
            tick_max = args.plot_tick_max
        elif args.plot_compact_range and selected_rows:
            tick_max = int(max(r.tick for r in selected_rows))
        else:
            run_ticks = int(manifest.get("ticks", 0) or 0)
            if run_ticks > 0:
                tick_max = run_ticks - 1
            elif rows:
                tick_max = int(max(r.tick for r in rows))
            else:
                tick_max = tick_min

        if tick_max < tick_min:
            raise ValueError("plot tick range is invalid: tick_max < tick_min")

        ascii_plot = build_ascii_packet_history(
            rows,
            selected,
            max(args.plot_cell_width, 8),
            tick_min,
            tick_max,
        )

        out_path = Path(args.plot_out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(ascii_plot, encoding="utf-8")
        print(f"wrote {out_path} (packets={len(selected)})")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
