#!/usr/bin/env python3
"""Simulate the chip-ID bootstrap protocol from the design markdown.

This is a toy software model of the protocol described in
`larpix_network_sim/CHIP_ID_BOOTSTRAP_SCRIPT_PLAN.md`.

Modeled state per chip:
- current CHIP_ID
- ENABLE_PISO_UP low 4 bits
- ENABLE_PISO_DOWN low 4 bits

Forwarding semantics:
- bootstrap CONFIG_WRITE packets propagate only through ENABLE_PISO_UP
- ENABLE_PISO_DOWN is tracked for protocol state / readback intent and display
- packet delivery is deterministic from the source chip along the currently
  enabled upstream path

This simulator is intended to catch:
- broken routes
- ambiguous routes
- wrong-target routes

and to show ASCII snapshots of chip ID / mask state at key milestones.
"""

from __future__ import annotations

import argparse
from collections import deque
from dataclasses import dataclass
from enum import IntEnum
from typing import Dict, Iterable, List, Set, Tuple


class Lane(IntEnum):
    NORTH = 0
    EAST = 1
    SOUTH = 2
    WEST = 3


DIRS = {
    Lane.NORTH: (0, 1),
    Lane.EAST: (1, 0),
    Lane.SOUTH: (0, -1),
    Lane.WEST: (-1, 0),
}


@dataclass
class Chip:
    chip_id: int = 1
    up_mask: int = 0x00
    down_mask: int = 0x00


Grid = List[List[Chip]]
Coord = Tuple[int, int]


def lane_mask(*lanes: Lane) -> int:
    value = 0
    for lane in lanes:
        value |= 1 << int(lane)
    return value


NORTH_ONLY = lane_mask(Lane.NORTH)
EAST_ONLY = lane_mask(Lane.EAST)
SOUTH_ONLY = lane_mask(Lane.SOUTH)
WEST_ONLY = lane_mask(Lane.WEST)
NORTH_EAST = lane_mask(Lane.NORTH, Lane.EAST)
NORTH_WEST = lane_mask(Lane.NORTH, Lane.WEST)
NORTH_EAST_WEST = lane_mask(Lane.NORTH, Lane.EAST, Lane.WEST)


class ProtocolError(RuntimeError):
    pass


class BootstrapSim:
    def __init__(self, cols: int, rows: int, s: int) -> None:
        if cols <= 0 or rows <= 0:
            raise ValueError("rows and cols must be positive")
        if not (0 <= s < cols):
            raise ValueError("source s must satisfy 0 <= s < cols")

        self.cols = cols
        self.rows = rows
        self.s = s
        self.source: Coord = (s, 0)
        self.grid: Grid = [[Chip() for _ in range(cols)] for _ in range(rows)]
        self.snapshots: Dict[str, str] = {}
        self.logs: List[str] = []

    def chip(self, coord: Coord) -> Chip:
        x, y = coord
        return self.grid[y][x]

    def coords(self) -> Iterable[Coord]:
        for y in range(self.rows):
            for x in range(self.cols):
                yield (x, y)

    def snapshot(self, title: str) -> None:
        self.snapshots[title] = self.render_grid(title)

    def render_grid(self, title: str) -> str:
        max_id = max(self.chip(c).chip_id for c in self.coords())
        cell_w = max(18, len(str(max_id)) + 14)

        def hline() -> str:
            return "+" + "+".join("-" * (cell_w + 2) for _ in range(self.cols)) + "+"

        lines = [title, hline()]
        for y in range(self.rows - 1, -1, -1):
            vals = []
            for x in range(self.cols):
                c = self.grid[y][x]
                vals.append(f"{c.chip_id}@U{c.up_mask & 0xF:04b}/D{c.down_mask & 0xF:04b}")
            lines.append("| " + " | ".join(f"{v:>{cell_w}}" for v in vals) + " |")
            lines.append(hline())
        lines.append("  " + "   ".join(f"x={x}" for x in range(self.cols)))
        lines.append(f"  top row is y={self.rows - 1}")
        lines.append("  bottom row is y=0")
        lines.append("  cell format = chip_id@Uupstreammask/Ddownstreammask")
        return "\n".join(lines)

    def neighbors_from_mask(self, coord: Coord, mask: int) -> Iterable[Coord]:
        x, y = coord
        for lane, (dx, dy) in DIRS.items():
            if mask & (1 << int(lane)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < self.cols and 0 <= ny < self.rows:
                    yield (nx, ny)

    def reachable_destinations(self, dest_id: int) -> Set[Coord]:
        q: deque[Coord] = deque([self.source])
        forwarded_seen: Set[Coord] = set()
        consumers: Set[Coord] = set()

        while q:
            coord = q.popleft()
            chip = self.chip(coord)
            if chip.chip_id == dest_id:
                consumers.add(coord)
                continue
            if coord in forwarded_seen:
                continue
            forwarded_seen.add(coord)
            for nxt in self.neighbors_from_mask(coord, chip.up_mask):
                q.append(nxt)
        return consumers

    def unique_destination(self, dest_id: int, expected: Coord, context: str) -> Coord:
        consumers = self.reachable_destinations(dest_id)
        if len(consumers) == 0:
            raise ProtocolError(f"{context}: broken route, no reachable chip with destination chip_id={dest_id}")
        if len(consumers) > 1:
            raise ProtocolError(
                f"{context}: ambiguous route, multiple reachable chips with destination chip_id={dest_id}: {sorted(consumers)}"
            )
        coord = next(iter(consumers))
        if coord != expected:
            raise ProtocolError(
                f"{context}: wrong target, packet destined for chip_id={dest_id} reached {coord}, expected {expected}"
            )
        return coord

    def write_chip_id(self, dest_id: int, expected: Coord, new_chip_id: int, context: str) -> None:
        coord = self.unique_destination(dest_id, expected, context)
        old = self.chip(coord).chip_id
        self.chip(coord).chip_id = new_chip_id
        self.logs.append(f"{context}: CHIP_ID write delivered to {coord}, chip_id {old} -> {new_chip_id}")

    def write_up(self, dest_id: int, expected: Coord, mask: int, context: str, *, replace: bool) -> None:
        coord = self.unique_destination(dest_id, expected, context)
        chip = self.chip(coord)
        old = chip.up_mask
        chip.up_mask = mask if replace else (chip.up_mask | mask)
        mode = "replace" if replace else "or"
        self.logs.append(
            f"{context}: ENABLE_PISO_UP ({mode}) delivered to {coord}, up_mask 0x{old:02X} -> 0x{chip.up_mask:02X}"
        )

    def write_down(self, dest_id: int, expected: Coord, mask: int, context: str, *, replace: bool = False) -> None:
        coord = self.unique_destination(dest_id, expected, context)
        chip = self.chip(coord)
        old = chip.down_mask
        chip.down_mask = mask if replace else (chip.down_mask | mask)
        if coord == self.source:
            chip.down_mask |= SOUTH_ONLY
        mode = "replace" if replace else "or"
        self.logs.append(
            f"{context}: ENABLE_PISO_DOWN ({mode}) delivered to {coord}, down_mask 0x{old:02X} -> 0x{chip.down_mask:02X}"
        )

    def bottom_row_id(self, desired: int) -> int:
        return 99 if desired == 1 else desired

    def target_coord(self, col: int, row: int) -> Coord:
        return (col, row)

    def final_bottom_up_mask(self, col: int) -> int:
        if col == self.s:
            mask = NORTH_ONLY
            if self.s > 0:
                mask |= WEST_ONLY
            if self.s < self.cols - 1:
                mask |= EAST_ONLY
            return mask
        if col < self.s:
            return NORTH_WEST if col > 0 else NORTH_ONLY
        if col > self.s:
            return NORTH_EAST if col < self.cols - 1 else NORTH_ONLY
        return NORTH_ONLY

    def prepare_source_special(self) -> None:
        mask = NORTH_ONLY
        if self.s > 0:
            mask |= WEST_ONLY
        if self.s < self.cols - 1:
            mask |= EAST_ONLY
        source_id = self.chip(self.source).chip_id
        self.write_up(source_id, self.source, mask, f"source special prepare for chip at {self.source}", replace=True)
        self.write_down(source_id, self.source, SOUTH_ONLY, f"source south downstream keep for chip at {self.source}")

    def bootstrap_vertical_column(self, c: int, prep_done: bool = False) -> None:
        bottom = (c, 0)
        bottom_id = self.chip(bottom).chip_id

        if not prep_done:
            if c < self.s:
                self.write_up(bottom_id, bottom, NORTH_ONLY, f"column {c} bottom prepare west-side north enable", replace=False)
            elif c > self.s:
                self.write_up(bottom_id, bottom, NORTH_ONLY, f"column {c} bottom prepare east-side north enable", replace=False)
            else:
                self.prepare_source_special()

        for y in range(0, self.rows - 1):
            current = (c, y)
            target = (c, y + 1)
            next_id = (y + 1) * self.cols + c
            self.write_chip_id(1, target, next_id, f"column {c} assign north neighbor of chip at {current}")
            self.write_down(next_id, target, SOUTH_ONLY, f"column {c} downstream return enable for chip at {target}")
            if y + 1 < self.rows - 1:
                self.write_up(next_id, target, NORTH_ONLY, f"column {c} north-only propagation enable for chip at {target}", replace=True)

    def run_bottom_row(self) -> None:
        source_id = self.bottom_row_id(self.s)
        self.write_chip_id(1, self.source, source_id, f"bottom-row source assignment (s={self.s})")

        if self.s < self.cols - 1:
            self.write_up(source_id, self.source, EAST_ONLY, f"bottom-row source east enable for chip at {self.source}", replace=True)

        for k in range(self.s, self.cols - 1):
            current = (k, 0)
            target = (k + 1, 0)
            current_id = self.chip(current).chip_id
            target_id = self.bottom_row_id(k + 1)
            if k > self.s:
                self.write_up(current_id, current, EAST_ONLY, f"bottom-row east-only upstream enable for chip at {current}", replace=True)
            self.write_chip_id(1, target, target_id, f"bottom-row assign east neighbor of chip at {current}")
            self.write_down(target_id, target, WEST_ONLY, f"bottom-row west downstream enable for chip at {target}")

        if self.s > 0:
            self.write_up(source_id, self.source, WEST_ONLY, f"bottom-row source west enable for chip at {self.source}", replace=True)

        for k in range(self.s, 0, -1):
            current = (k, 0)
            target = (k - 1, 0)
            current_id = self.chip(current).chip_id
            target_id = self.bottom_row_id(k - 1)
            if k < self.s:
                self.write_up(current_id, current, WEST_ONLY, f"bottom-row west-only upstream enable for chip at {current}", replace=True)
            self.write_chip_id(1, target, target_id, f"bottom-row assign west neighbor of chip at {current}")
            self.write_down(target_id, target, EAST_ONLY, f"bottom-row east downstream enable for chip at {target}")

    def run_cleanup_remap(self) -> None:
        placeholder = None
        for coord in self.coords():
            if self.chip(coord).chip_id == 99:
                placeholder = coord
                break
        if placeholder is None:
            return
        ones = [coord for coord in self.coords() if self.chip(coord).chip_id == 1]
        if ones:
            raise ProtocolError(f"cleanup remap: cannot rewrite placeholder while chip_id=1 still exists at {sorted(ones)}")
        self.unique_destination(99, placeholder, "cleanup remap route check")
        old = self.chip(placeholder).chip_id
        self.chip(placeholder).chip_id = 1
        self.logs.append(f"cleanup remap: chip at {placeholder} remapped chip_id {old} -> 1")

    def run(self) -> None:
        self.chip(self.source).down_mask = SOUTH_ONLY
        self.snapshot("Initial Configuration")

        self.run_bottom_row()
        self.snapshot("After Bottom Row Assigned")

        self.bootstrap_vertical_column(0, prep_done=False)
        self.snapshot("After First Column Assigned")

        if self.cols > 1:
            if self.s == 1:
                self.prepare_source_special()
                self.bootstrap_vertical_column(1, prep_done=True)
            else:
                bottom = (1, 0)
                bottom_id = self.chip(bottom).chip_id
                self.write_up(bottom_id, bottom, NORTH_ONLY, f"second-column bottom prepare for chip at {bottom}", replace=False)
                self.bootstrap_vertical_column(1, prep_done=True)

        for c in range(2, self.cols):
            if c == self.s:
                self.prepare_source_special()
                self.bootstrap_vertical_column(c, prep_done=True)
            else:
                self.bootstrap_vertical_column(c, prep_done=False)

        # Normalize final bottom-row upstream state to the intended steady bootstrap result.
        for c in range(self.cols):
            coord = (c, 0)
            chip_id = self.chip(coord).chip_id
            self.write_up(chip_id, coord, self.final_bottom_up_mask(c), f"final bottom-row normalize for chip at {coord}", replace=True)

        self.run_cleanup_remap()
        self.snapshot("After Full Protocol Completed")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Simulate the chip-ID bootstrap protocol from the markdown")
    parser.add_argument("rows", type=int, help="number of rows")
    parser.add_argument("cols", type=int, help="number of columns")
    parser.add_argument("s", type=int, help="source chip x-position on bottom row")
    parser.add_argument("--show-log", action="store_true", help="print the step-by-step protocol log")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    sim = BootstrapSim(args.cols, args.rows, args.s)
    try:
        sim.run()
        status = "PASS: protocol completed without broken, ambiguous, or wrong-target routing"
    except ProtocolError as exc:
        status = f"FAIL: {exc}"

    print(f"Bootstrap simulation for rows={args.rows}, cols={args.cols}, s={args.s}")
    print(status)
    print()

    order = [
        "Initial Configuration",
        "After Bottom Row Assigned",
        "After First Column Assigned",
        "After Full Protocol Completed",
    ]
    for i, title in enumerate(order):
        if i:
            print()
        print(sim.snapshots.get(title, title + "\n<milestone not reached>"))

    if args.show_log:
        print()
        print("Step Log")
        for line in sim.logs:
            print(f"- {line}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
