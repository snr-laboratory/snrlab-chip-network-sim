#!/usr/bin/env python3
"""Generate startup JSON for live bootstrap CHIP_ID assignment tests.

This helper builds the startup frame schedule for an arbitrary `rows x cols`
network with source chip `(source_x, source_y)`. The generated JSON mirrors the
current logic in `bootstrap_id_protocol_sim.py` and inserts an immediate
`CHIP_ID` read after every chip-ID reassignment so the FPGA controller can
confirm each new ID before continuing.
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

CHIP_ID_REG = 122
ENABLE_PISO_UP_REG = 124
ENABLE_PISO_DOWN_REG = 125
PLACEHOLDER_CHIP_ID = 254


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
    def __init__(
        self,
        cols: int,
        rows: int,
        source_x: int,
        source_y: int = 0,
        *,
        tick_start: int = 20,
        tick_step: int = 120,
    ) -> None:
        if cols <= 0 or rows <= 0:
            raise ValueError("rows and cols must be positive")
        if cols * rows > 254:
            raise ValueError(
                "bootstrap protocol reserves chip ID 254 as a placeholder and chip ID 255 is reserved by the RTL as GLOBAL_ID, so the maximum supported network size is 254 chips"
            )
        if not (0 <= source_x < cols):
            raise ValueError("source_x must satisfy 0 <= source_x < cols")
        if not (0 <= source_y < rows):
            raise ValueError("source_y must satisfy 0 <= source_y < rows")
        self.cols = cols
        self.rows = rows
        self.source_x = source_x
        self.source_y = source_y
        self.tick = tick_start
        self.tick_step = tick_step
        self.frames: list[FrameSpec] = []
        self.ids = [[1 for _ in range(cols)] for _ in range(rows)]
        self.up = [[0 for _ in range(cols)] for _ in range(rows)]
        self.down = [[0 for _ in range(cols)] for _ in range(rows)]
        self.source = (source_x, source_y)

    def chip_id_at(self, x: int, y: int) -> int:
        return self.ids[y][x]

    def set_chip_id_at(self, x: int, y: int, chip_id: int) -> None:
        self.ids[y][x] = chip_id

    def desired_chip_id(self, x: int, y: int) -> int:
        desired = y * self.cols + x
        return PLACEHOLDER_CHIP_ID if desired == 1 else desired

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

    def assign_with_immediate_readback(
        self,
        x: int,
        y: int,
        new_id: int,
        down_mask: int,
        assign_label: str,
        down_label: str,
        read_label: str,
    ) -> None:
        self.assign_chip_id(x, y, new_id, assign_label)
        self.write_down(x, y, down_mask, down_label)
        self.add_read_wait(new_id, CHIP_ID_REG, read_label)

    def prepare_source_row_path(self, target_x: int) -> None:
        if target_x == self.source_x:
            return
        step = 1 if target_x > self.source_x else -1
        lane_only = EAST_ONLY if step > 0 else WEST_ONLY
        direction = "east" if step > 0 else "west"

        self.write_up(
            self.source_x,
            self.source_y,
            lane_only,
            f"source-row path prepare toward column {target_x} via {direction} from ({self.source_x},{self.source_y})",
            replace=True,
        )

        x = self.source_x + step
        while x != target_x:
            self.write_up(
                x,
                self.source_y,
                lane_only,
                f"source-row relay prepare toward column {target_x} via {direction} for chip at ({x},{self.source_y})",
                replace=True,
            )
            x += step

    def assign_source_row(self) -> None:
        source_id = self.desired_chip_id(self.source_x, self.source_y)
        self.assign_chip_id(self.source_x, self.source_y, source_id, f"source assignment at ({self.source_x},{self.source_y})")
        self.write_down(self.source_x, self.source_y, SOUTH_ONLY, f"source south downstream keep for chip at ({self.source_x},{self.source_y})")
        self.add_read_wait(source_id, CHIP_ID_REG, f"read CHIP_ID from chip {source_id} at ({self.source_x},{self.source_y})")

        if self.source_x < self.cols - 1:
            self.write_up(self.source_x, self.source_y, EAST_ONLY, f"source-row east prepare for chip at ({self.source_x},{self.source_y})", replace=True)
            for x in range(self.source_x, self.cols - 1):
                if x > self.source_x:
                    self.write_up(x, self.source_y, EAST_ONLY, f"source-row east-only propagation enable for chip at ({x},{self.source_y})", replace=True)
                target_x = x + 1
                target_id = self.desired_chip_id(target_x, self.source_y)
                self.assign_with_immediate_readback(
                    target_x,
                    self.source_y,
                    target_id,
                    WEST_ONLY,
                    f"source-row assign east neighbor of chip at ({x},{self.source_y})",
                    f"source-row west downstream enable for chip at ({target_x},{self.source_y})",
                    f"read CHIP_ID from chip {target_id} at ({target_x},{self.source_y})",
                )

        if self.source_x > 0:
            self.write_up(self.source_x, self.source_y, WEST_ONLY, f"source-row west prepare for chip at ({self.source_x},{self.source_y})", replace=True)
            for x in range(self.source_x, 0, -1):
                if x < self.source_x:
                    self.write_up(x, self.source_y, WEST_ONLY, f"source-row west-only propagation enable for chip at ({x},{self.source_y})", replace=True)
                target_x = x - 1
                target_id = self.desired_chip_id(target_x, self.source_y)
                self.assign_with_immediate_readback(
                    target_x,
                    self.source_y,
                    target_id,
                    EAST_ONLY,
                    f"source-row assign west neighbor of chip at ({x},{self.source_y})",
                    f"source-row east downstream enable for chip at ({target_x},{self.source_y})",
                    f"read CHIP_ID from chip {target_id} at ({target_x},{self.source_y})",
                )

    def bootstrap_vertical_direction(self, col: int, *, upward: bool) -> None:
        if upward and self.source_y == self.rows - 1:
            return
        if not upward and self.source_y == 0:
            return

        lane_only = NORTH_ONLY if upward else SOUTH_ONLY
        down_mask = SOUTH_ONLY if upward else NORTH_ONLY
        direction = "north" if upward else "south"
        step = 1 if upward else -1
        boundary = self.rows - 1 if upward else 0

        self.prepare_source_row_path(col)
        self.write_up(col, self.source_y, lane_only, f"column {col} root prepare {direction} enable for chip at ({col},{self.source_y})", replace=True)

        y = self.source_y
        while y != boundary:
            target_y = y + step
            target_id = self.desired_chip_id(col, target_y)
            self.assign_with_immediate_readback(
                col,
                target_y,
                target_id,
                down_mask,
                f"column {col} assign {direction} neighbor of chip at ({col},{y})",
                f"column {col} downstream return enable for chip at ({col},{target_y})",
                f"read CHIP_ID from chip {target_id} at ({col},{target_y})",
            )
            if target_y != boundary:
                self.write_up(col, target_y, lane_only, f"column {col} {direction}-only propagation enable for chip at ({col},{target_y})", replace=True)
            y = target_y

    def final_source_row_up_mask(self, col: int) -> int:
        mask = 0
        if col < self.source_x and col > 0:
            mask |= WEST_ONLY
        elif col > self.source_x and col < self.cols - 1:
            mask |= EAST_ONLY
        else:
            if col == self.source_x:
                if self.source_x > 0:
                    mask |= WEST_ONLY
                if self.source_x < self.cols - 1:
                    mask |= EAST_ONLY
        if self.source_y < self.rows - 1:
            mask |= NORTH_ONLY
        if self.source_y > 0:
            mask |= SOUTH_ONLY
        return mask

    def final_vertical_up_mask(self, row: int) -> int:
        if row > self.source_y:
            return NORTH_ONLY if row < self.rows - 1 else 0
        if row < self.source_y:
            return SOUTH_ONLY if row > 0 else 0
        return 0

    def normalize_final_up_masks(self) -> None:
        row_order = [self.source_x]
        row_order.extend(range(self.source_x - 1, -1, -1))
        row_order.extend(range(self.source_x + 1, self.cols))

        for x in row_order:
            self.write_up(x, self.source_y, self.final_source_row_up_mask(x), f"final source-row normalize for chip at ({x},{self.source_y})", replace=True)

        for x in row_order:
            for y in range(self.source_y + 1, self.rows):
                self.write_up(x, y, self.final_vertical_up_mask(y), f"final north-column normalize for chip at ({x},{y})", replace=True)
            for y in range(self.source_y - 1, -1, -1):
                self.write_up(x, y, self.final_vertical_up_mask(y), f"final south-column normalize for chip at ({x},{y})", replace=True)

    def run_cleanup_remap(self) -> None:
        for y in range(self.rows):
            for x in range(self.cols):
                if self.ids[y][x] == PLACEHOLDER_CHIP_ID:
                    self.add_write(PLACEHOLDER_CHIP_ID, CHIP_ID_REG, 1, f"cleanup remap {PLACEHOLDER_CHIP_ID} -> 1 at ({x},{y})")
                    self.ids[y][x] = 1
                    self.add_read_wait(1, CHIP_ID_REG, f"read CHIP_ID from chip 1 at ({x},{y}) after cleanup")
                    return

    def build(self) -> list[FrameSpec]:
        self.assign_source_row()
        for col in range(self.cols):
            self.bootstrap_vertical_direction(col, upward=True)
            self.bootstrap_vertical_direction(col, upward=False)
        self.normalize_final_up_masks()
        self.run_cleanup_remap()
        return self.frames


def resolve_source_x(args: argparse.Namespace) -> int:
    if args.source_x is not None:
        return args.source_x
    if args.s is not None:
        return args.s
    raise ValueError("either --s or --source-x must be provided")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate startup JSON for bootstrap CHIP_ID assignment plus immediate readback for arbitrary rows/cols/source"
    )
    parser.add_argument("--rows", type=int, required=True)
    parser.add_argument("--cols", type=int, required=True)
    parser.add_argument("--s", type=int)
    parser.add_argument("--source-x", type=int)
    parser.add_argument("--source-y", type=int, default=0)
    parser.add_argument("--out", required=True)
    parser.add_argument("--tick-start", type=int, default=20)
    parser.add_argument("--tick-step", type=int, default=120)
    args = parser.parse_args()

    source_x = resolve_source_x(args)
    frames = Builder(
        args.cols,
        args.rows,
        source_x,
        args.source_y,
        tick_start=args.tick_start,
        tick_step=args.tick_step,
    ).build()
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
