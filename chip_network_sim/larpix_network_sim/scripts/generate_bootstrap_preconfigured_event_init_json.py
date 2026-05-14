#!/usr/bin/env python3
"""Generate per-runtime RTL register preload JSON for a preconfigured event run.

This uses the existing bootstrap CHIP_ID-assignment logic to derive the final
steady-state register values that would exist after the protocol completes, but
it writes those values directly into each RTL instance before tick 0.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

THIS_DIR = Path(__file__).resolve().parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

from generate_bootstrap_chip_id_readback_json import (
    Builder,
    CHIP_ID_REG,
    ENABLE_PISO_UP_REG,
    ENABLE_PISO_DOWN_REG,
)

CSA_ENABLE_BASE = 66
ENABLE_TRIG_MODES_REG = 128
CHANNEL_MASK_BASE = 131


def parse_targets(args: argparse.Namespace) -> list[tuple[int, int]]:
    targets: list[tuple[int, int]] = []
    if args.target_x is not None or args.target_y is not None:
        if args.target_x is None or args.target_y is None:
            raise SystemExit('both --target-x and --target-y must be provided together')
        targets.append((args.target_x, args.target_y))
    for raw in args.target or []:
        parts = raw.split(',')
        if len(parts) != 2:
            raise SystemExit(f'invalid --target value: {raw!r}; expected x,y')
        try:
            x = int(parts[0])
            y = int(parts[1])
        except ValueError as exc:
            raise SystemExit(f'invalid --target value: {raw!r}; expected integers') from exc
        targets.append((x, y))
    if not targets:
        raise SystemExit('at least one target chip must be provided')

    deduped: list[tuple[int, int]] = []
    seen: set[tuple[int, int]] = set()
    for x, y in targets:
        if not (0 <= x < args.cols and 0 <= y < args.rows):
            raise SystemExit(f'target coordinates out of range: ({x},{y})')
        if (x, y) not in seen:
            seen.add((x, y))
            deduped.append((x, y))
    return deduped


def main() -> int:
    ap = argparse.ArgumentParser(description='Generate RTL register preload JSON from bootstrap final state plus event-chip setup')
    ap.add_argument('--rows', type=int, required=True)
    ap.add_argument('--cols', type=int, required=True)
    ap.add_argument('--s', type=int, required=True)
    ap.add_argument('--source-y', type=int, default=0)
    ap.add_argument('--target-x', type=int)
    ap.add_argument('--target-y', type=int)
    ap.add_argument('--target', action='append', default=[], help='repeatable target chip coordinate in x,y form')
    ap.add_argument('--out', required=True)
    args = ap.parse_args()

    targets = parse_targets(args)

    builder = Builder(args.cols, args.rows, args.s, args.source_y)
    builder.build()

    writes = []
    for y in range(args.rows):
        for x in range(args.cols):
            runtime_id = y * args.cols + x
            writes.append({
                'runtime_id': runtime_id,
                'register_addr': CHIP_ID_REG,
                'register_data': int(builder.ids[y][x]),
                'label': f'bootstrap final CHIP_ID for chip at ({x},{y})',
            })
            writes.append({
                'runtime_id': runtime_id,
                'register_addr': ENABLE_PISO_UP_REG,
                'register_data': int(builder.up[y][x]) & 0xF,
                'label': f'bootstrap final ENABLE_PISO_UP for chip at ({x},{y})',
            })
            writes.append({
                'runtime_id': runtime_id,
                'register_addr': ENABLE_PISO_DOWN_REG,
                'register_data': int(builder.down[y][x]) & 0xF,
                'label': f'bootstrap final ENABLE_PISO_DOWN for chip at ({x},{y})',
            })

    target_entries = []
    for target_x, target_y in targets:
        target_runtime_id = target_y * args.cols + target_x
        target_chip_id = int(builder.ids[target_y][target_x])
        target_entries.append({
            'x': target_x,
            'y': target_y,
            'runtime_id': target_runtime_id,
            'chip_id': target_chip_id,
        })
        for reg in range(CSA_ENABLE_BASE, CSA_ENABLE_BASE + 8):
            writes.append({
                'runtime_id': target_runtime_id,
                'register_addr': reg,
                'register_data': 0xFF,
                'label': f'enable CSA channels byte {reg - CSA_ENABLE_BASE} on chip {target_chip_id}',
            })
        for reg in range(CHANNEL_MASK_BASE, CHANNEL_MASK_BASE + 8):
            writes.append({
                'runtime_id': target_runtime_id,
                'register_addr': reg,
                'register_data': 0x00,
                'label': f'unmask channels byte {reg - CHANNEL_MASK_BASE} on chip {target_chip_id}',
            })
        writes.append({
            'runtime_id': target_runtime_id,
            'register_addr': ENABLE_TRIG_MODES_REG,
            'register_data': 0x00,
            'label': f'disable trigger veto modes on chip {target_chip_id}',
        })

    out = {
        'mode': 'rtl_preconfigured',
        'rows': args.rows,
        'cols': args.cols,
        's': args.s,
        'source_y': args.source_y,
        'targets': target_entries,
        'register_writes': writes,
    }
    if len(target_entries) == 1:
        out['target_runtime_id'] = target_entries[0]['runtime_id']
        out['target_chip_id'] = target_entries[0]['chip_id']
    Path(args.out).write_text(json.dumps(out, indent=2) + '\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
