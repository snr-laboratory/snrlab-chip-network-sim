#!/usr/bin/env python3
"""Generate startup JSON for the 3x5 live bootstrap CHIP_ID test.

This helper builds the startup frame schedule for the `rows=3`, `cols=5`,
`source s=0` network bootstrap/readback test. The generated JSON follows the
corrected toy bootstrap protocol and inserts an immediate `CHIP_ID` read after
all chip-ID reassignments so the FPGA controller can confirm each new ID before
continuing.
"""
from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path

NORTH = 0x01
EAST = 0x02
SOUTH = 0x04
WEST = 0x08

NORTH_ONLY = NORTH
EAST_ONLY = EAST
SOUTH_ONLY = SOUTH
WEST_ONLY = WEST
NORTH_EAST = NORTH | EAST
NORTH_WEST = NORTH | WEST

CHIP_ID_REG = 122
ENABLE_PISO_UP_REG = 124
ENABLE_PISO_DOWN_REG = 125


@dataclass
class FrameSpec:
    tick_start: int
    type: str
    chip_id: int
    register_addr: int
    register_data: int | None = None
    label: str = ""
    wait_for_chip_id_reply: int | None = None


class Builder:
    def __init__(self, cols: int, rows: int, s: int, *, tick_start: int = 20, tick_step: int = 120) -> None:
        if cols <= 0 or rows <= 0:
            raise ValueError("rows and cols must be positive")
        if not (0 <= s < cols):
            raise ValueError("s must satisfy 0 <= s < cols")
        self.cols = cols
        self.rows = rows
        self.s = s
        self.tick = tick_start
        self.tick_step = tick_step
        self.frames: list[FrameSpec] = []
        self.ids = [[1 for _ in range(cols)] for _ in range(rows)]
        self.up = [[0 for _ in range(cols)] for _ in range(rows)]
        self.down = [[0 for _ in range(cols)] for _ in range(rows)]
        self.source = (s, 0)

    def chip_id_at(self, x: int, y: int) -> int:
        return self.ids[y][x]

    def set_chip_id_at(self, x: int, y: int, chip_id: int) -> None:
        self.ids[y][x] = chip_id

    def add_write(self, dest_id: int, reg: int, data: int, label: str) -> None:
        self.frames.append(FrameSpec(self.tick, "write", dest_id, reg, data, label))
        self.tick += self.tick_step

    def add_read_wait(self, dest_id: int, reg: int, label: str) -> None:
        self.frames.append(FrameSpec(self.tick, "read", dest_id, reg, None, label, wait_for_chip_id_reply=dest_id))
        self.tick += self.tick_step

    def write_up(self, x: int, y: int, mask: int, label: str, *, replace: bool) -> None:
        chip_id = self.chip_id_at(x, y)
        old = self.up[y][x]
        new = mask if replace else (old | mask)
        self.up[y][x] = new
        self.add_write(chip_id, ENABLE_PISO_UP_REG, new, label)

    def write_down(self, x: int, y: int, mask: int, label: str, *, replace: bool = False) -> None:
        chip_id = self.chip_id_at(x, y)
        old = self.down[y][x]
        new = mask if replace else (old | mask)
        if (x, y) == self.source:
            new |= SOUTH_ONLY
        self.down[y][x] = new
        self.add_write(chip_id, ENABLE_PISO_DOWN_REG, new, label)

    def assign_chip_id(self, x: int, y: int, new_id: int, label: str) -> None:
        self.add_write(1, CHIP_ID_REG, new_id, label)
        self.set_chip_id_at(x, y, new_id)

    def assign_with_immediate_readback(self, x: int, y: int, new_id: int, down_mask: int, assign_label: str, down_label: str, read_label: str) -> None:
        self.assign_chip_id(x, y, new_id, assign_label)
        self.write_down(x, y, down_mask, down_label)
        self.add_read_wait(new_id, CHIP_ID_REG, read_label)

    def bottom_row_id(self, desired: int) -> int:
        return 99 if desired == 1 else desired

    def prepare_source_special(self) -> None:
        mask = NORTH_ONLY
        if self.s > 0:
            mask |= WEST_ONLY
        if self.s < self.cols - 1:
            mask |= EAST_ONLY
        self.write_up(self.s, 0, mask, f"source special prepare for chip at ({self.s},0)", replace=True)
        self.write_down(self.s, 0, SOUTH_ONLY, f"source south downstream keep for chip at ({self.s},0)")

    def bootstrap_vertical_column(self, c: int, *, prep_done: bool = False) -> None:
        if not prep_done:
            if c < self.s:
                self.write_up(c, 0, NORTH_ONLY, f"column {c} bottom prepare west-side north enable", replace=False)
            elif c > self.s:
                self.write_up(c, 0, NORTH_ONLY, f"column {c} bottom prepare east-side north enable", replace=False)
            else:
                self.prepare_source_special()

        for y in range(0, self.rows - 1):
            next_id = (y + 1) * self.cols + c
            self.assign_with_immediate_readback(
                c,
                y + 1,
                next_id,
                SOUTH_ONLY,
                f"column {c} assign north neighbor of chip at ({c},{y})",
                f"column {c} downstream return enable for chip at ({c},{y + 1})",
                f"read CHIP_ID from chip {next_id} at ({c},{y + 1})",
            )
            if y + 1 < self.rows - 1:
                self.write_up(c, y + 1, NORTH_ONLY, f"column {c} north-only propagation enable for chip at ({c},{y + 1})", replace=True)

    def run_bottom_row(self) -> None:
        source_id = self.bottom_row_id(self.s)
        self.assign_chip_id(self.s, 0, source_id, f"bottom-row source assignment (s={self.s})")
        self.write_down(self.s, 0, SOUTH_ONLY, f"bottom-row source south enable at ({self.s},0)")
        self.add_read_wait(source_id, CHIP_ID_REG, f"read CHIP_ID from chip {source_id} at ({self.s},0)")

        if self.s < self.cols - 1:
            self.write_up(self.s, 0, EAST_ONLY, f"bottom-row source east enable for chip at ({self.s},0)", replace=True)

        for k in range(self.s, self.cols - 1):
            if k > self.s:
                self.write_up(k, 0, EAST_ONLY, f"bottom-row east-only upstream enable for chip at ({k},0)", replace=True)
            target_id = self.bottom_row_id(k + 1)
            self.assign_with_immediate_readback(
                k + 1,
                0,
                target_id,
                WEST_ONLY,
                f"bottom-row assign east neighbor of chip at ({k},0)",
                f"bottom-row west downstream enable for chip at ({k + 1},0)",
                f"read CHIP_ID from chip {target_id} at ({k + 1},0)",
            )

        if self.s > 0:
            self.write_up(self.s, 0, WEST_ONLY, f"bottom-row source west enable for chip at ({self.s},0)", replace=True)

        for k in range(self.s, 0, -1):
            if k < self.s:
                self.write_up(k, 0, WEST_ONLY, f"bottom-row west-only upstream enable for chip at ({k},0)", replace=True)
            target_id = self.bottom_row_id(k - 1)
            self.assign_with_immediate_readback(
                k - 1,
                0,
                target_id,
                EAST_ONLY,
                f"bottom-row assign west neighbor of chip at ({k},0)",
                f"bottom-row east downstream enable for chip at ({k - 1},0)",
                f"read CHIP_ID from chip {target_id} at ({k - 1},0)",
            )

    def run_cleanup_remap(self) -> None:
        for x in range(self.cols):
            if self.ids[0][x] == 99:
                self.add_write(99, CHIP_ID_REG, 1, f"cleanup remap 99 -> 1 at ({x},0)")
                self.ids[0][x] = 1
                self.add_read_wait(1, CHIP_ID_REG, f"read CHIP_ID from chip 1 at ({x},0) after cleanup")
                break

    def build(self) -> list[FrameSpec]:
        self.run_bottom_row()
        self.bootstrap_vertical_column(0, prep_done=False)
        if self.cols > 1:
            if self.s == 1:
                self.prepare_source_special()
                self.bootstrap_vertical_column(1, prep_done=True)
            else:
                self.write_up(1, 0, NORTH_ONLY, "second-column bottom prepare for chip at (1,0)", replace=False)
                self.bootstrap_vertical_column(1, prep_done=True)
        for c in range(2, self.cols):
            if c == self.s:
                self.prepare_source_special()
                self.bootstrap_vertical_column(c, prep_done=True)
            else:
                self.bootstrap_vertical_column(c, prep_done=False)
        self.run_cleanup_remap()
        return self.frames


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate startup JSON for bootstrap CHIP_ID assignment plus immediate readback")
    parser.add_argument("--rows", type=int, required=True)
    parser.add_argument("--cols", type=int, required=True)
    parser.add_argument("--s", type=int, required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--tick-start", type=int, default=20)
    parser.add_argument("--tick-step", type=int, default=120)
    args = parser.parse_args()

    frames = Builder(args.cols, args.rows, args.s, tick_start=args.tick_start, tick_step=args.tick_step).build()
    out = {
        "frames": [
            {
                "tick_start": f.tick_start,
                "type": f.type,
                "chip_id": f.chip_id,
                "register_addr": f.register_addr,
                **({"register_data": f.register_data} if f.register_data is not None else {}),
                **({"wait_for_chip_id_reply": f.wait_for_chip_id_reply} if f.wait_for_chip_id_reply is not None else {}),
                "label": f.label,
            }
            for f in frames
        ]
    }
    Path(args.out).write_text(json.dumps(out, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
