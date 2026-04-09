#!/usr/bin/env python3
"""Generate startup JSON for a bootstrap-plus-remote-event network test.

This helper first builds the normal CHIP_ID bootstrap schedule using the live
bootstrap generator logic, removes the per-assignment CHIP_ID readbacks for a
shorter event testbench, then appends the additional config writes needed to
prepare one target chip for a multi-channel natural analog hit:
- enable all 64 channels in CSA_ENABLE
- unmask all 64 channels in CHANNEL_MASK
- disable trigger-veto behavior for a clean first event test

The intended use is a live network event test where bootstrap establishes the
routing tree and a later charge stimulus is injected into all 64 channels of
one remote chip.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

THIS_DIR = Path(__file__).resolve().parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

from generate_bootstrap_chip_id_readback_json import Builder, PLACEHOLDER_CHIP_ID

CSA_ENABLE_BASE = 66
ENABLE_TRIG_MODES_REG = 128
CHANNEL_MASK_BASE = 131


def main() -> int:
    ap = argparse.ArgumentParser(description='Generate startup JSON for bootstrap plus remote analog-event test')
    ap.add_argument('--rows', type=int, required=True)
    ap.add_argument('--cols', type=int, required=True)
    ap.add_argument('--s', type=int, required=True)
    ap.add_argument('--target-x', type=int, required=True)
    ap.add_argument('--target-y', type=int, required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--tick-start', type=int, default=20)
    ap.add_argument('--tick-step', type=int, default=120)
    args = ap.parse_args()

    if not (0 <= args.target_x < args.cols and 0 <= args.target_y < args.rows):
        raise SystemExit('target coordinates out of range')

    builder = Builder(args.cols, args.rows, args.s, tick_start=args.tick_start, tick_step=args.tick_step)
    builder.build()
    builder.frames = [f for f in builder.frames if f.type != 'read']

    target_id = args.target_y * args.cols + args.target_x
    if target_id == 1:
        raise SystemExit('target final chip ID 1 collides with bootstrap special handling; choose a different target for this test')
    if target_id == PLACEHOLDER_CHIP_ID:
        raise SystemExit('target final chip ID equals bootstrap placeholder; choose a different target for this test')

    for reg in range(CSA_ENABLE_BASE, CSA_ENABLE_BASE + 8):
        builder.add_write(target_id, reg, 0xFF, f'enable CSA channels byte {reg - CSA_ENABLE_BASE} on chip {target_id}')
    for reg in range(CHANNEL_MASK_BASE, CHANNEL_MASK_BASE + 8):
        builder.add_write(target_id, reg, 0x00, f'unmask channels byte {reg - CHANNEL_MASK_BASE} on chip {target_id}')
    builder.add_write(target_id, ENABLE_TRIG_MODES_REG, 0x00, f'disable trigger veto modes on chip {target_id}')

    out = {
        'frames': [
            {
                'tick_start': f.tick_start,
                'type': f.type,
                'chip_id': f.chip_id,
                'register_addr': f.register_addr,
                **({'register_data': f.register_data} if f.register_data is not None else {}),
                **({'wait_for_chip_id_reply': f.wait_for_chip_id_reply} if f.wait_for_chip_id_reply is not None else {}),
                'label': f.label,
            }
            for f in builder.frames
        ]
    }
    Path(args.out).write_text(json.dumps(out, indent=2) + '\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
