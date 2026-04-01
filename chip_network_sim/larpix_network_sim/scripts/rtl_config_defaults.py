#!/usr/bin/env python3
"""Helpers for extracting startup config-register defaults from mirrored LArPix RTL."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def parse_value(token: str) -> int:
    token = token.strip()
    if token.startswith("8'h") or token.startswith("8'H"):
        return int(token[3:], 16)
    if token.startswith("8'b") or token.startswith("8'B"):
        return int(token[3:], 2)
    if token.startswith("8'd") or token.startswith("8'D"):
        return int(token[3:], 10)
    raise ValueError(f"unsupported value token: {token}")


def parse_constants(constants_path: Path) -> dict[str, int]:
    constants: dict[str, int] = {}
    pat = re.compile(r"localparam\s+int\s+(\w+)\s*=\s*(\d+)\s*;")
    for line in constants_path.read_text().splitlines():
        m = pat.search(line)
        if m:
            constants[m.group(1)] = int(m.group(2))
    return constants


def parse_defaults(constants_path: Path, assign_path: Path) -> dict[int, int]:
    consts = parse_constants(constants_path)
    defaults: dict[int, int] = {}
    lines = assign_path.read_text().splitlines()
    one_pat = re.compile(r"config_bits\[(\w+)\]\s*<=\s*(8'[hHbBdD][0-9A-Fa-f]+)\s*;")
    loop_pat = re.compile(r"for\s*\(int\s+i\s*=\s*0;\s*i\s*<\s*(\d+)\s*;\s*i\+\+\)\s*config_bits\[(\w+)\s*\+\s*i\]\s*<=\s*(8'[hHbBdD][0-9A-Fa-f]+)\s*;")
    for idx, line in enumerate(lines):
        if 'RESET_CYCLES' in line and 'for' in line and 'i < 3' in line:
            base = consts['RESET_CYCLES']
            defaults[base + 0] = 0x00
            defaults[base + 1] = 0x10
            defaults[base + 2] = 0x00
            continue
        m = loop_pat.search(line)
        if m:
            count = int(m.group(1))
            base = consts[m.group(2)]
            value = parse_value(m.group(3))
            for i in range(count):
                defaults[base + i] = value
            continue
        m = one_pat.search(line)
        if m:
            defaults[consts[m.group(1)]] = parse_value(m.group(2))
            continue
    return dict(sorted(defaults.items()))


def main() -> int:
    parser = argparse.ArgumentParser(description='Dump mirrored RTL startup config defaults as JSON')
    parser.add_argument('--constants', default='larpix_network_sim/larpix_v3b_rtl/src/larpix_constants.sv')
    parser.add_argument('--assign', default='larpix_network_sim/larpix_v3b_rtl/src/config_regfile_assign.sv')
    args = parser.parse_args()
    defaults = parse_defaults(Path(args.constants), Path(args.assign))
    print(json.dumps({str(k): v for k, v in defaults.items()}, indent=2, sort_keys=True))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
