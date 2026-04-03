#!/usr/bin/env python3
"""Generate FPGA startup config writes for the LArPix chip-ID bootstrap protocol.

This file mirrors the logic in bootstrap_id_protocol_sim.py but is kept separate
so the simulator remains unchanged. It emits a startup JSON file containing the
sequence of CONFIG_WRITE packets that the FPGA controller should inject into the
network to assign chip IDs according to the bootstrap protocol.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path

NORTH_ONLY = 0x01
EAST_ONLY = 0x02
WEST_ONLY = 0x08
NORTH_WEST = 0x09
NORTH_EAST = 0x03
NORTH_EAST_WEST = 0x0B
CHIP_ID_REG = 122
ENABLE_PISO_DOWN_REG = 125


@dataclass
class FrameSpec:
    tick_start: int
    type: str
    chip_id: int
    register_addr: int
    register_data: int
    label: str


class BootstrapStartupBuilder:
    def __init__(self, m: int, n: int, s: int, *, tick_start: int = 20, tick_step: int = 120) -> None:
        if m <= 0 or n <= 0:
            raise ValueError('m and n must be positive')
        if not (0 <= s < m):
            raise ValueError('s must satisfy 0 <= s < m')
        self.m = m
        self.n = n
        self.s = s
        self.tick = tick_start
        self.tick_step = tick_step
        self.frames: list[FrameSpec] = []

    def bootstrap_bottom_row_id(self, desired_chip_id: int) -> int:
        return 99 if desired_chip_id == 1 else desired_chip_id

    def add_write(self, dest_id: int, register_addr: int, register_data: int, label: str) -> None:
        self.frames.append(
            FrameSpec(
                tick_start=self.tick,
                type='write',
                chip_id=dest_id,
                register_addr=register_addr,
                register_data=register_data,
                label=label,
            )
        )
        self.tick += self.tick_step

    def run_bottom_row(self) -> None:
        source_id = self.bootstrap_bottom_row_id(self.s)
        self.add_write(1, CHIP_ID_REG, source_id, f'bottom-row source assignment (s={self.s})')

        for k in range(self.s, self.m - 1):
            current_id = self.bootstrap_bottom_row_id(k)
            target_id = self.bootstrap_bottom_row_id(k + 1)
            self.add_write(current_id, ENABLE_PISO_DOWN_REG, EAST_ONLY, f'bottom-row east enable for x={k}')
            self.add_write(1, CHIP_ID_REG, target_id, f'bottom-row assign east neighbor of x={k}')

        for k in range(self.s, 0, -1):
            current_id = self.bootstrap_bottom_row_id(k)
            target_id = self.bootstrap_bottom_row_id(k - 1)
            self.add_write(current_id, ENABLE_PISO_DOWN_REG, WEST_ONLY, f'bottom-row west enable for x={k}')
            self.add_write(1, CHIP_ID_REG, target_id, f'bottom-row assign west neighbor of x={k}')

    def run_first_column(self) -> None:
        for y in range(0, self.n - 1):
            current_id = y * self.m
            next_id = (y + 1) * self.m
            mask = NORTH_EAST if (self.s == 0 and y == 0 and self.m > 1) else NORTH_ONLY
            self.add_write(current_id, ENABLE_PISO_DOWN_REG, mask, f'first-column north enable for y={y}')
            self.add_write(1, CHIP_ID_REG, next_id, f'first-column assign north neighbor of y={y}')

    def bottom_cell_mask_for_column(self, c: int) -> int:
        if c == 0:
            return NORTH_ONLY
        if c < self.s:
            return NORTH_WEST
        if c == self.s:
            return NORTH_EAST_WEST
        if c < self.m - 1:
            return NORTH_EAST
        return NORTH_ONLY

    def run_column_from_bottom(self, c: int) -> None:
        bottom_id = self.bootstrap_bottom_row_id(c)
        self.add_write(bottom_id, ENABLE_PISO_DOWN_REG, self.bottom_cell_mask_for_column(c), f'column {c} bottom-cell prepare')

        for y in range(0, self.n - 1):
            next_id = (y + 1) * self.m + c
            self.add_write(1, CHIP_ID_REG, next_id, f'column {c} assign north neighbor of y={y}')
            if y + 1 < self.n - 1:
                current_id = (y + 1) * self.m + c
                self.add_write(current_id, ENABLE_PISO_DOWN_REG, NORTH_ONLY, f'column {c} north-only enable for y={y + 1}')

    def run_remaining_columns(self) -> None:
        for c in range(1, self.m):
            self.run_column_from_bottom(c)

    def run_cleanup_remap(self) -> None:
        if 0 <= 1 < self.m and self.bootstrap_bottom_row_id(1) == 99:
            self.add_write(99, CHIP_ID_REG, 1, 'cleanup remap 99 -> 1')

    def build(self) -> list[FrameSpec]:
        self.run_bottom_row()
        self.run_first_column()
        self.run_remaining_columns()
        self.run_cleanup_remap()
        return self.frames


def main() -> int:
    parser = argparse.ArgumentParser(description='Generate startup JSON for the bootstrap chip-ID protocol')
    parser.add_argument('--rows', type=int, required=True, help='number of rows')
    parser.add_argument('--cols', type=int, required=True, help='number of columns')
    parser.add_argument('--s', type=int, required=True, help='source x position on bottom row')
    parser.add_argument('--out', required=True, help='output startup JSON path')
    parser.add_argument('--tick-start', type=int, default=20, help='tick for first frame')
    parser.add_argument('--tick-step', type=int, default=120, help='tick spacing between frames')
    args = parser.parse_args()

    frames = BootstrapStartupBuilder(args.cols, args.rows, args.s, tick_start=args.tick_start, tick_step=args.tick_step).build()
    out = {
        'frames': [
            {
                'tick_start': frame.tick_start,
                'type': frame.type,
                'chip_id': frame.chip_id,
                'register_addr': frame.register_addr,
                'register_data': frame.register_data,
                'label': frame.label,
            }
            for frame in frames
        ]
    }
    Path(args.out).write_text(json.dumps(out, indent=2) + '\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
