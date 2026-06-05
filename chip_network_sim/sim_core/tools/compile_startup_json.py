#!/usr/bin/env python3
"""Compile a startup JSON description into scheduled LArPix UART frames.

Input schema:
{
  "frames": [
    {
      "tick_start": 0,
      "type": "write",
      "chip_id": 1,
      "register_addr": 122,
      "register_data": 2,
      "label": "set source chip id"
    }
  ],
  "readback_phase": {
    "start_tick": 1000,
    "requests": [
      {
        "type": "read",
        "chip_id": 0,
        "register_addr": 122,
        "label": "read CHIP_ID from chip 0"
      }
    ]
  }
}

Output schema:
{
  "frames": [
    {
      "tick_start": 0,
      "label": "set source chip id",
      "packet_word": "0x...",
      "uart_bits": [0, 1, ...]
    }
  ],
  "readback_phase": {
    "start_tick": 1000,
    "requests": [
      {
        "label": "read CHIP_ID from chip 0",
        "packet_word": "0x...",
        "uart_bits": [0, 1, ...]
      }
    ]
  }
}
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from larpix_uart import (
    build_config_read_packet,
    build_config_write_packet,
    packet_to_uart_bits,
)

FRAME_BITS = 66


def strip_json_line_comments(text: str) -> str:
    lines = []
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("//"):
            continue
        lines.append(line)
    return "\n".join(lines) + ("\n" if text.endswith("\n") else "")


def compile_frame(spec: dict[str, Any]) -> dict[str, Any]:
    tick_start = int(spec.get("tick_start", 0))
    kind = spec["type"]
    chip_id = int(spec["chip_id"])
    label = str(spec.get("label", ""))

    if kind == "write":
        word = build_config_write_packet(
            chip_id=chip_id,
            register_addr=int(spec["register_addr"]),
            register_data=int(spec["register_data"]),
        )
    elif kind == "read":
        word = build_config_read_packet(
            chip_id=chip_id,
            register_addr=int(spec["register_addr"]),
            stats_nibble=int(spec.get("stats_nibble", 0)),
        )
    elif kind == "word":
        word = int(str(spec["packet_word"]), 0)
    else:
        raise ValueError(f"unknown frame type: {kind}")

    uart_bits = packet_to_uart_bits(word).bits
    if len(uart_bits) != FRAME_BITS:
        raise ValueError(f"expected {FRAME_BITS} UART bits, got {len(uart_bits)}")

    out = {
        "tick_start": tick_start,
        "label": label,
        "packet_word": f"0x{word:016x}",
        "uart_bits": uart_bits,
    }
    if "wait_for_chip_id_reply" in spec:
        out["wait_for_chip_id_reply"] = int(spec["wait_for_chip_id_reply"])
    return out


def compile_readback_phase(spec: dict[str, Any] | None) -> dict[str, Any] | None:
    if spec is None:
        return None
    start_tick = int(spec['start_tick'])
    requests = spec.get('requests', [])
    if not isinstance(requests, list):
        raise ValueError('readback_phase.requests must be a list')
    compiled_requests = [compile_frame(req) for req in requests]
    for req in compiled_requests:
        req.pop('tick_start', None)
    return {
        'start_tick': start_tick,
        'requests': compiled_requests,
    }


def check_overlaps(frames: list[dict[str, Any]]) -> None:
    ordered = sorted(frames, key=lambda f: int(f['tick_start']))
    for prev, curr in zip(ordered, ordered[1:]):
        prev_end = int(prev['tick_start']) + FRAME_BITS
        curr_start = int(curr['tick_start'])
        if curr_start < prev_end:
            raise ValueError(
                f"overlapping frames: '{prev.get('label', '')}' ending at tick {prev_end - 1} "
                f"overlaps frame starting at tick {curr_start}"
            )


def main() -> int:
    parser = argparse.ArgumentParser(description='Compile startup JSON into scheduled UART frames')
    parser.add_argument('input_json', help='startup JSON input')
    parser.add_argument('output_json', help='compiled startup schedule JSON output')
    args = parser.parse_args()

    raw = json.loads(strip_json_line_comments(Path(args.input_json).read_text()))
    input_frames = raw.get("frames", [])
    if not isinstance(input_frames, list):
        raise SystemExit("input JSON must contain a list field 'frames'")

    compiled_frames = [compile_frame(frame) for frame in input_frames]
    compiled_readback = compile_readback_phase(raw.get('readback_phase'))
    check_overlaps(compiled_frames)

    out = {
        'frame_bits': FRAME_BITS,
        'frames': sorted(compiled_frames, key=lambda f: int(f['tick_start'])),
    }
    if compiled_readback is not None:
        out['readback_phase'] = compiled_readback
    Path(args.output_json).write_text(json.dumps(out, indent=2) + '\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
