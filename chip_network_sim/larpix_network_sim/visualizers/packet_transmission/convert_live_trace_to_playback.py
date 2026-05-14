#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict, deque
from dataclasses import dataclass
from pathlib import Path
from typing import Deque, Dict, Iterable, List, Tuple

THIS_DIR = Path(__file__).resolve().parent
REPO_ROOT = THIS_DIR.parents[2]
SCRIPTS_DIR = REPO_ROOT / "larpix_network_sim" / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from larpix_uart import decode_packet

FULL_FRAME_BITS = 66
MSG_FRAME_BITS = 9
CHIP_ID_REG = 122
ENABLE_PISO_UP_REG = 124
ENABLE_PISO_DOWN_REG = 125

EDGE_TO_DELTA = {
    "north": (0, 1),
    "east": (1, 0),
    "south": (0, -1),
    "west": (-1, 0),
}

MSG_TAG_NAMES = {
    0: "N",
    1: "E",
    2: "S",
    3: "W",
}


@dataclass
class Chip:
    chip_id: int = 1
    up_mask: int = 0
    down_mask: int = 0


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Convert a live chip trace JSONL into visualizer playback JSON")
    ap.add_argument("--rows", type=int, required=True)
    ap.add_argument("--cols", type=int, required=True)
    ap.add_argument("--source-x", type=int, required=True)
    ap.add_argument("--source-y", type=int, default=0)
    ap.add_argument("--startup-json", default=None)
    ap.add_argument("--init-regs-json", default=None)
    ap.add_argument("--run-log", required=True)
    ap.add_argument("--trace-jsonl", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--name", default=None)
    ap.add_argument("--rtl-version", default=None)
    return ap.parse_args()


def make_grid(rows: int, cols: int, source_x: int, source_y: int) -> List[List[Chip]]:
    return [[Chip() for _ in range(cols)] for _ in range(rows)]


def chip(grid: List[List[Chip]], coord: Tuple[int, int]) -> Chip:
    x, y = coord
    return grid[y][x]


def coords(rows: int, cols: int) -> Iterable[Tuple[int, int]]:
    for y in range(rows):
        for x in range(cols):
            yield (x, y)


def initial_chips(grid: List[List[Chip]], rows: int, cols: int) -> List[dict]:
    out = []
    for x, y in coords(rows, cols):
        c = chip(grid, (x, y))
        out.append({"x": x, "y": y, "chip_id": c.chip_id, "up_mask": c.up_mask, "down_mask": c.down_mask})
    return out


def neighbors_from_mask(coord: Tuple[int, int], mask: int, rows: int, cols: int) -> List[Tuple[int, int]]:
    x, y = coord
    out = []
    for bit, (dx, dy) in enumerate(EDGE_TO_DELTA.values()):
        if (mask >> bit) & 1:
            nx, ny = x + dx, y + dy
            if 0 <= nx < cols and 0 <= ny < rows:
                out.append((nx, ny))
    return out


def unique_reachable_destination(
    grid: List[List[Chip]],
    rows: int,
    cols: int,
    source: Tuple[int, int],
    dest_id: int,
) -> Tuple[int, int]:
    q = deque([source])
    seen = {source}
    matches = []
    while q:
        cur = q.popleft()
        c = chip(grid, cur)
        if c.chip_id == dest_id:
            matches.append(cur)
        for nxt in neighbors_from_mask(cur, c.up_mask, rows, cols):
            if nxt not in seen:
                seen.add(nxt)
                q.append(nxt)
    if len(matches) != 1:
        raise ValueError(f"destination chip_id {dest_id} not uniquely reachable, matches={matches}")
    return matches[0]


def parse_run_log(path: Path) -> Tuple[List[dict], List[dict]]:
    tx_re = re.compile(r"transmitted frame at seq=(\d+)\s*:\s*(0x[0-9a-fA-F]+)(?: label=(.*))?$")
    rx_re = re.compile(r"received packet at seq=(\d+):\s*(0x[0-9a-fA-F]+)$")
    tx = []
    rx = []
    for line in path.read_text().splitlines():
        m = tx_re.search(line)
        if m:
            tx.append({"seq": int(m.group(1)), "packet_word": m.group(2), "label": m.group(3) or ""})
            continue
        m = rx_re.search(line)
        if m:
            rx.append({"seq": int(m.group(1)), "packet_word": m.group(2)})
    return tx, rx


def packet_type_name(word_hex: str) -> str:
    fields = decode_packet(int(word_hex, 16))
    if fields.kind == "msg":
        return "msg_packet"
    if fields.kind == "config_write":
        return "config_write"
    if fields.kind == "config_read":
        return "config_read_reply" if fields.decoded.get("downstream") == 1 else "config_read_request"
    if fields.kind == "data":
        return "event_data"
    return "packet"


def frame_bits_for_word(word_hex: str) -> int:
    fields = decode_packet(int(word_hex, 16))
    if fields.kind == "msg":
        return MSG_FRAME_BITS
    return FULL_FRAME_BITS


def mask_direction_name(mask: int) -> str | None:
    names = {1: "North", 2: "East", 4: "South", 8: "West"}
    return names.get(mask)


def packet_label(word_hex: str) -> str:
    fields = decode_packet(int(word_hex, 16))
    decoded = fields.decoded
    chip_id = decoded.get('chip_id')
    reg = decoded.get('register_addr')
    data = int(decoded.get('register_data', 0))
    if fields.kind == "msg":
        tx_tag = int(decoded.get('tx_tag', 0))
        fifo_state = int(decoded.get('fifo_state', 0))
        return f"tag[{MSG_TAG_NAMES.get(tx_tag, '?')}] state[{fifo_state:02b}]"
    if fields.kind == "data":
        return f"Event data from chip {chip_id} channel {decoded.get('channel_id')}"
    if fields.kind == "config_write":
        if reg == CHIP_ID_REG:
            return f"Set CHIP_ID={data} for chip {chip_id}"
        if reg == ENABLE_PISO_UP_REG:
            direction = mask_direction_name(data & 0xF)
            return f"{direction} upstream TX enable for chip {chip_id}" if direction else f"Upstream TX mask 0x{data & 0xF:X} for chip {chip_id}"
        if reg == ENABLE_PISO_DOWN_REG:
            direction = mask_direction_name(data & 0xF)
            return f"{direction} downstream TX enable for chip {chip_id}" if direction else f"Downstream TX mask 0x{data & 0xF:X} for chip {chip_id}"
        return f"Write reg {reg} = 0x{data:02X} for chip {chip_id}"
    if fields.kind == "config_read":
        if reg == CHIP_ID_REG:
            return f"Read CHIP_ID from chip {chip_id}"
        return f"Read reg {reg} from chip {chip_id}"
    return fields.kind


def decoded_packet_summary(word_hex: str) -> dict:
    fields = decode_packet(int(word_hex, 16))
    return {
        "kind": fields.kind,
        "decoded": fields.decoded,
        "odd_parity_ok": bool(fields.odd_parity_ok),
    }

def build_fpga_events(startup_frames: List[dict], tx_log: List[dict], rx_log: List[dict]) -> List[dict]:
    fpga_events = []
    if startup_frames:
        if len(tx_log) != len(startup_frames):
            raise SystemExit(f"transmitted frame count mismatch: startup has {len(startup_frames)}, log has {len(tx_log)}")
        for frame, tx_entry in zip(startup_frames, tx_log):
            tick_start = int(frame["tick_start"])
            frame_bits = frame_bits_for_word(tx_entry["packet_word"])
            fpga_events.append({
                "direction": "tx",
                "start_tick": tick_start,
                "end_tick": tick_start + frame_bits,
                "complete_tick": int(tx_entry["seq"]),
                "packet_word": tx_entry["packet_word"],
                "packet_type": packet_type_name(tx_entry["packet_word"]),
                "label": frame.get("label") or packet_label(tx_entry["packet_word"]),
                "decode": decoded_packet_summary(tx_entry["packet_word"]),
            })
    for rx_entry in rx_log:
        complete_tick = int(rx_entry["seq"])
        frame_bits = frame_bits_for_word(rx_entry["packet_word"])
        start_tick = max(0, complete_tick - frame_bits + 1)
        fpga_events.append({
            "direction": "rx",
            "start_tick": start_tick,
            "end_tick": complete_tick + 1,
            "complete_tick": complete_tick,
            "packet_word": rx_entry["packet_word"],
            "packet_type": packet_type_name(rx_entry["packet_word"]),
            "label": packet_label(rx_entry["packet_word"]),
            "decode": decoded_packet_summary(rx_entry["packet_word"]),
        })
    fpga_events.sort(key=lambda item: (item["start_tick"], item["direction"], item["packet_word"]))
    return fpga_events


def rtl_shared_fifo_depth() -> int:
    rtl_path = REPO_ROOT / "larpix_network_sim" / "larpix_v3b_rtl" / "src" / "digital_core.sv"
    for line in rtl_path.read_text().splitlines():
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        match = re.search(r"parameter\s+integer\s+unsigned\s+FIFO_DEPTH\s*=\s*(\d+)", stripped)
        if match:
            return int(match.group(1))
    raise SystemExit(f"could not determine active FIFO_DEPTH from {rtl_path}")


def runtime_to_coord(runtime_id: int, cols: int) -> Tuple[int, int]:
    return (runtime_id % cols, runtime_id // cols)


def neighbor_runtime(runtime_id: int, edge: str, rows: int, cols: int) -> int | None:
    x, y = runtime_to_coord(runtime_id, cols)
    dx, dy = EDGE_TO_DELTA[edge]
    nx = x + dx
    ny = y + dy
    if 0 <= nx < cols and 0 <= ny < rows:
        return ny * cols + nx
    return None


def load_init_register_writes(path: Path | None) -> List[dict]:
    if path is None:
        return []
    raw = json.loads(path.read_text())
    return list(raw.get("register_writes", []))


def apply_init_register_writes(grid: List[List[Chip]], cols: int, register_writes: List[dict]) -> None:
    for entry in register_writes:
        runtime_id = int(entry.get("runtime_id", -1))
        reg = int(entry.get("register_addr", -1))
        data = int(entry.get("register_data", 0))
        if runtime_id < 0:
            continue
        x, y = runtime_to_coord(runtime_id, cols)
        c = chip(grid, (x, y))
        if reg == CHIP_ID_REG:
            c.chip_id = data
        elif reg == ENABLE_PISO_UP_REG:
            c.up_mask = data & 0xF
        elif reg == ENABLE_PISO_DOWN_REG:
            c.down_mask = data & 0xF


def parse_trace_jsonl(path: Path) -> List[dict]:
    events = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if line:
            events.append(json.loads(line))
    return events


def build_packet_spans(trace_events: List[dict], rows: int, cols: int) -> List[dict]:
    pending_tx: Dict[Tuple[int, int, str], Deque[dict]] = defaultdict(deque)
    pending_rx: Dict[Tuple[int, int, str], Deque[dict]] = defaultdict(deque)
    spans = []

    def append_span(tx_event: dict, rx_event: dict, src_runtime: int, dst_runtime: int) -> None:
        tx_seq = int(tx_event["seq"])
        rx_seq = int(rx_event["seq"])
        frame_bits = frame_bits_for_word(rx_event["packet_word"])
        start_tick = max(0, tx_seq - frame_bits + 1)
        end_tick = max(start_tick + 1, rx_seq + 1)
        packet_type = packet_type_name(rx_event["packet_word"])
        spans.append({
            "type": "packet_move",
            "start_tick": start_tick,
            "end_tick": end_tick,
            "src": list(runtime_to_coord(src_runtime, cols)),
            "dst": list(runtime_to_coord(dst_runtime, cols)),
            "packet_type": packet_type,
            "packet_word": rx_event["packet_word"],
            "label": packet_label(rx_event["packet_word"]),
            "tx_complete_tick": tx_seq,
            "rx_complete_tick": rx_seq,
        })

    for event in trace_events:
        event_name = event.get("event")
        if event_name not in {"tx_packet", "rx_packet"}:
            continue
        edge = event.get("edge", "")
        if edge not in EDGE_TO_DELTA:
            continue

        if event_name == "tx_packet":
            src_runtime = int(event["runtime_id"])
            dst_runtime = neighbor_runtime(src_runtime, edge, rows, cols)
            if dst_runtime is None:
                continue
            key = (src_runtime, dst_runtime, event["packet_word"])
            rx_queue = pending_rx.get(key)
            if rx_queue:
                rx_event = rx_queue.popleft()
                if not rx_queue:
                    pending_rx.pop(key, None)
                append_span(event, rx_event, src_runtime, dst_runtime)
            else:
                pending_tx[key].append(event)
            continue

        dst_runtime = int(event["runtime_id"])
        src_runtime = neighbor_runtime(dst_runtime, edge, rows, cols)
        if src_runtime is None:
            continue
        key = (src_runtime, dst_runtime, event["packet_word"])
        tx_queue = pending_tx.get(key)
        if tx_queue:
            tx_event = tx_queue.popleft()
            if not tx_queue:
                pending_tx.pop(key, None)
            append_span(tx_event, event, src_runtime, dst_runtime)
        else:
            pending_rx[key].append(event)

    unmatched_tx = sum(len(v) for v in pending_tx.values())
    unmatched_rx = sum(len(v) for v in pending_rx.values())
    if unmatched_rx or unmatched_tx:
        print(
            f"warning: trace packet pairing mismatch: unmatched_tx={unmatched_tx} unmatched_rx={unmatched_rx}",
            file=sys.stderr,
        )

    spans.sort(key=lambda item: (item["start_tick"], item["end_tick"], item["src"], item["dst"]))
    return spans


def build_rx_event_queues(trace_events: List[dict]) -> Dict[Tuple[int, str], Deque[dict]]:
    rx_by_runtime_and_word: Dict[Tuple[int, str], Deque[dict]] = defaultdict(deque)
    for event in trace_events:
        if event.get("event") != "rx_packet":
            continue
        runtime_id = int(event.get("runtime_id", -1))
        packet_word = event.get("packet_word")
        if runtime_id < 0 or not isinstance(packet_word, str):
            continue
        rx_by_runtime_and_word[(runtime_id, packet_word)].append(event)
    return rx_by_runtime_and_word

def build_charge_events(trace_events: List[dict], cols: int) -> List[dict]:
    grouped: Dict[Tuple[int, int], dict] = {}
    for event in trace_events:
        if event.get("event") != "charge_injected":
            continue
        runtime_id = int(event["runtime_id"])
        tick = int(event["seq"])
        key = (tick, runtime_id)
        x, y = runtime_to_coord(runtime_id, cols)
        entry = grouped.setdefault(key, {
            "tick": tick,
            "event": "charge_injected",
            "x": x,
            "y": y,
            "runtime_id": runtime_id,
            "channels": [],
            "channel_count": 0,
            "total_charge": 0.0,
        })
        entry["channels"].append(int(event.get("channel", 0)))
        entry["channel_count"] += 1
        entry["total_charge"] += float(event.get("value_f64", 0.0))

    chip_events = list(grouped.values())
    for entry in chip_events:
        entry["channels"].sort()
    chip_events.sort(key=lambda item: (item["tick"], item["runtime_id"]))
    return chip_events


def build_data_packet_metrics(trace_events: List[dict], rx_log: List[dict], charge_events: List[dict], initial_chip_entries: List[dict]) -> dict:
    generated_by_chip_words: Dict[int, set[str]] = defaultdict(set)
    received_by_chip_words: Dict[int, set[str]] = defaultdict(set)
    total_arrivals_by_chip: Dict[int, int] = defaultdict(int)
    coord_to_chip_id = {(int(entry["x"]), int(entry["y"])): int(entry.get("chip_id", 1)) for entry in initial_chip_entries}

    for event in trace_events:
        if event.get("event") != "tx_packet":
            continue
        packet_word = event.get("packet_word")
        if not isinstance(packet_word, str):
            continue
        fields = decode_packet(int(packet_word, 16))
        if fields.kind != "data":
            continue
        origin_chip_id = int(fields.decoded.get("chip_id", -1))
        if origin_chip_id < 0:
            continue
        generated_by_chip_words[origin_chip_id].add(packet_word)

    for rx_entry in rx_log:
        packet_word = rx_entry.get("packet_word")
        if not isinstance(packet_word, str):
            continue
        fields = decode_packet(int(packet_word, 16))
        if fields.kind != "data":
            continue
        origin_chip_id = int(fields.decoded.get("chip_id", -1))
        if origin_chip_id < 0:
            continue
        received_by_chip_words[origin_chip_id].add(packet_word)
        total_arrivals_by_chip[origin_chip_id] += 1

    charge_chip_ids = set()
    for event in charge_events:
        coord = (int(event.get("x", -1)), int(event.get("y", -1)))
        chip_id = coord_to_chip_id.get(coord)
        if chip_id is not None:
            charge_chip_ids.add(chip_id)

    all_chip_ids = sorted(charge_chip_ids | set(generated_by_chip_words) | set(received_by_chip_words) | set(total_arrivals_by_chip))
    generated_by_chip = []
    total_generated = 0
    total_received = 0
    total_arrivals = 0

    for chip_id in all_chip_ids:
        generated_count = len(generated_by_chip_words.get(chip_id, set()))
        received_count = len(received_by_chip_words.get(chip_id, set()))
        arrival_count = int(total_arrivals_by_chip.get(chip_id, 0))
        total_generated += generated_count
        total_received += received_count
        total_arrivals += arrival_count
        generated_by_chip.append({
            "chip_id": chip_id,
            "generated_count": generated_count,
            "received_at_fpga_count": received_count,
            "total_arrivals_at_fpga_count": arrival_count,
            "delivery_ratio": (received_count / generated_count) if generated_count > 0 else None,
        })

    total_lost = max(0, total_generated - total_received)
    return {
        "generated_by_chip": generated_by_chip,
        "total_generated": total_generated,
        "total_received_at_fpga": total_received,
        "total_arrivals_at_fpga": total_arrivals,
        "total_lost": total_lost,
        "delivery_ratio": (total_received / total_generated) if total_generated > 0 else None,
    }


def build_shared_fifo_updates(trace_events: List[dict], cols: int) -> Tuple[List[dict], int]:
    updates: List[dict] = []
    last_by_runtime: Dict[int, int] = {}
    max_occupancy = 0
    for event in trace_events:
        if event.get("event") != "shared_fifo_occupancy":
            continue
        runtime_id = int(event.get("runtime_id", -1))
        if runtime_id < 0:
            continue
        occupancy = int(event.get("value_u32", 0))
        max_occupancy = max(max_occupancy, occupancy)
        if last_by_runtime.get(runtime_id) == occupancy:
            continue
        last_by_runtime[runtime_id] = occupancy
        x, y = runtime_to_coord(runtime_id, cols)
        updates.append({
            "tick": int(event.get("seq", 0)),
            "x": x,
            "y": y,
            "runtime_id": runtime_id,
            "shared_fifo_occupancy": occupancy,
        })
    updates.sort(key=lambda item: (item["tick"], item["runtime_id"]))
    return updates, max_occupancy


def build_runtime_lane_updates(trace_events: List[dict], cols: int) -> List[dict]:
    updates: List[dict] = []
    for event in trace_events:
        if event.get("event") != "lane_state":
            continue
        runtime_id = int(event.get("runtime_id", -1))
        if runtime_id < 0:
            continue
        packed = int(event.get("value_u32", 0))
        up_mask = packed & 0xF
        down_mask = (packed >> 4) & 0xF
        x, y = runtime_to_coord(runtime_id, cols)
        updates.append({
            "tick": int(event.get("seq", 0)),
            "x": x,
            "y": y,
            "runtime_id": runtime_id,
            "up_mask": up_mask,
            "down_mask": down_mask,
            "event": "lane_state",
            "label": f"Lane state U=0x{up_mask:X} D=0x{down_mask:X}",
        })
    updates.sort(key=lambda item: (item["tick"], item["runtime_id"]))
    return updates


def build_chip_updates_and_fpga_spans(
    grid: List[List[Chip]],
    rows: int,
    cols: int,
    source: Tuple[int, int],
    startup_frames: List[dict],
    tx_log: List[dict],
    rx_log: List[dict],
    trace_events: List[dict],
) -> Tuple[List[dict], List[dict]]:
    if len(tx_log) != len(startup_frames):
        raise SystemExit(f"transmitted frame count mismatch: startup has {len(startup_frames)}, log has {len(tx_log)}")

    chip_updates = []
    fpga_spans = []
    rx_index = 0
    rx_event_queues = build_rx_event_queues(trace_events)

    for frame, tx_entry in zip(startup_frames, tx_log):
        tick_start = int(frame["tick_start"])
        tx_end = int(tx_entry["seq"])
        frame_bits = frame_bits_for_word(tx_entry["packet_word"])
        fields = decode_packet(int(tx_entry["packet_word"], 16))
        decoded = fields.decoded
        dest_id = int(decoded.get("chip_id", 1))
        target = unique_reachable_destination(grid, rows, cols, source, dest_id)

        fpga_spans.append({
            "start_tick": tick_start,
            "end_tick": tick_start + frame_bits,
            "packet_type": packet_type_name(tx_entry["packet_word"]),
            "packet_word": tx_entry["packet_word"],
            "label": frame.get("label", ""),
        })

        reg = decoded.get("register_addr")
        data = decoded.get("register_data")
        if fields.kind == "config_write" and reg is not None and data is not None:
            target_runtime_id = target[1] * cols + target[0]
            rx_queue = rx_event_queues.get((target_runtime_id, tx_entry["packet_word"]))
            if not rx_queue:
                raise SystemExit(f"missing destination rx_packet for config write word {tx_entry['packet_word']} at runtime {target_runtime_id}")
            arrival_tick = int(rx_queue.popleft()["seq"])
            c = chip(grid, target)
            update = {
                "tick": arrival_tick,
                "x": target[0],
                "y": target[1],
                "register_addr": int(reg),
                "register_data": int(data),
                "label": packet_label(tx_entry["packet_word"]),
                "event": "config_applied",
            }
            if reg == CHIP_ID_REG:
                c.chip_id = int(data)
                update["chip_id"] = c.chip_id
            elif reg == ENABLE_PISO_UP_REG:
                c.up_mask = int(data) & 0xF
                update["up_mask"] = c.up_mask
            elif reg == ENABLE_PISO_DOWN_REG:
                c.down_mask = int(data) & 0xF
                update["down_mask"] = c.down_mask
            chip_updates.append(update)

        if fields.kind == "config_read":
            if rx_index >= len(rx_log):
                raise SystemExit("missing readback packets in run log")
            rx_index += 1

    return chip_updates, fpga_spans


def main() -> int:
    args = parse_args()
    source = (args.source_x, args.source_y)
    startup_frames = []
    if args.startup_json is not None:
        startup = json.loads(Path(args.startup_json).read_text())
        startup_frames = startup.get("frames", [])
    tx_log, rx_log = parse_run_log(Path(args.run_log))
    trace_events = parse_trace_jsonl(Path(args.trace_jsonl))
    init_register_writes = load_init_register_writes(Path(args.init_regs_json) if args.init_regs_json else None)

    initial_grid = make_grid(args.rows, args.cols, args.source_x, args.source_y)
    apply_init_register_writes(initial_grid, args.cols, init_register_writes)
    chip_state_grid = make_grid(args.rows, args.cols, args.source_x, args.source_y)
    apply_init_register_writes(chip_state_grid, args.cols, init_register_writes)
    chip_updates = []
    fpga_spans = []
    fpga_events = build_fpga_events(startup_frames, tx_log, rx_log)
    if startup_frames:
        chip_updates, fpga_spans = build_chip_updates_and_fpga_spans(
            chip_state_grid, args.rows, args.cols, source, startup_frames, tx_log, rx_log, trace_events
        )
    chip_updates.extend(build_runtime_lane_updates(trace_events, args.cols))
    chip_updates.sort(key=lambda item: (item["tick"], item["x"], item["y"], item.get("event", "")))
    charge_events = build_charge_events(trace_events, args.cols)
    shared_fifo_updates, shared_fifo_max = build_shared_fifo_updates(trace_events, args.cols)
    shared_fifo_capacity = rtl_shared_fifo_depth()
    initial_chip_entries = initial_chips(initial_grid, args.rows, args.cols)
    data_packet_metrics = build_data_packet_metrics(trace_events, rx_log, charge_events, initial_chip_entries)

    playback = {
        "name": args.name or f"Live trace playback {args.rows}x{args.cols}",
        "rtl_version": args.rtl_version,
        "rows": args.rows,
        "cols": args.cols,
        "source": {"x": args.source_x, "y": args.source_y},
        "total_ticks": max(
            [0]
            + [int(item["seq"]) for item in tx_log]
            + [int(item["seq"]) for item in rx_log]
            + [int(item["seq"]) for item in trace_events]
        ) + 50,
        "initial_chips": initial_chip_entries,
        "chip_updates": chip_updates,
        "chip_events": charge_events,
        "data_packet_metrics": data_packet_metrics,
        "shared_fifo_updates": shared_fifo_updates,
        "shared_fifo_max": shared_fifo_max,
        "shared_fifo_capacity": shared_fifo_capacity,
        "packet_spans": build_packet_spans(trace_events, args.rows, args.cols),
        "fpga_spans": fpga_spans,
        "fpga_events": fpga_events,
    }

    Path(args.out).write_text(json.dumps(playback, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
