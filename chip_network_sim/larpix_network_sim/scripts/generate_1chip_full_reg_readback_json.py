#!/usr/bin/env python3
""" Helper script to create the configuration file used in the single chip register readback test run."""
""" This file converts the RTL's declared startup register defaults (from larpix_v3b_rtl/src/larpix_constants.sv and larpix_v3b/src/config_regfile_assign.sv) into an FPGA packet schedule for the 1 chip register verification test """
from __future__ import annotations

import argparse
import json
from pathlib import Path

from rtl_config_defaults import parse_defaults

WRITE_TICK = 20
FIRST_READ_TICK = 140
READ_SPACING = 120
MODIFIED_REGISTER_ADDR = 125

HEADER = """// 1-chip exhaustive LArPix startup/readback test configuration.
//
// Test intent:
// - enable south TX on the single directly connected chip so config-read replies
//   can return to the FPGA over the south edge
// - issue a CONFIG_READ for every explicit startup-default register described in
//   the mirrored RTL default-assignment file
// - skip register 125 because the first write in this test intentionally changes
//   ENABLE_PISO_DOWN from its RTL default 0x00 to 0x04
//
// Expected behavior:
// - every CONFIG_READ reply should match the RTL startup-default value for that
//   register, except register 125 which is intentionally modified first
// - outputs the configuration file used for the simulation run (config/startup_1chip_full_reg_readback.json) 
// - the paired runner script checks the returned reply set exhaustively

"""


def build_frames(defaults: dict[int, int]) -> list[dict[str, int | str]]:
    frames: list[dict[str, int | str]] = [
        {
            'tick_start': WRITE_TICK,
            'type': 'write',
            'chip_id': 1,
            'register_addr': MODIFIED_REGISTER_ADDR,
            'register_data': 4,
            'label': 'enable source south tx lane',
        }
    ]
    tick = FIRST_READ_TICK
    for addr in sorted(defaults):
        if addr == MODIFIED_REGISTER_ADDR:
            continue
        frames.append({
            'tick_start': tick,
            'type': 'read',
            'chip_id': 1,
            'register_addr': addr,
            'label': f'read startup register {addr}',
        })
        tick += READ_SPACING
    return frames


def main() -> int:
    parser = argparse.ArgumentParser(description='Generate exhaustive 1-chip startup-readback JSON')
    parser.add_argument('--constants', default='larpix_network_sim/larpix_v3b_rtl/src/larpix_constants.sv')
    parser.add_argument('--assign', default='larpix_network_sim/larpix_v3b_rtl/src/config_regfile_assign.sv')
    parser.add_argument('--out', default='larpix_network_sim/config/startup_1chip_full_reg_readback.json')
    args = parser.parse_args()

    defaults = parse_defaults(Path(args.constants), Path(args.assign))
    frames = build_frames(defaults)
    body = json.dumps({'frames': frames}, indent=2) + '\n'
    Path(args.out).write_text(HEADER + body)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
