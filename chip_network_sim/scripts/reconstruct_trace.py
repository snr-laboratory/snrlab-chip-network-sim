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


def main() -> int:
    ap = argparse.ArgumentParser(description="Reconstruct packet timelines from tracebin logs")
    ap.add_argument("-run", "--run-dir", required=True, help="Trace run directory")
    ap.add_argument("--top", type=int, default=20, help="Show top-N packets in summary")
    ap.add_argument("--json-out", help="Optional path to write full JSON summary")
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

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
