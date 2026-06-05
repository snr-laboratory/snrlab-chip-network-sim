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
PLACEHOLDER_CHIP_ID = 254


class ProtocolError(RuntimeError):
    pass


def opposite_lane(lane: Lane) -> Lane:
    return {
        Lane.NORTH: Lane.SOUTH,
        Lane.SOUTH: Lane.NORTH,
        Lane.EAST: Lane.WEST,
        Lane.WEST: Lane.EAST,
    }[lane]


class BootstrapSim:
    def __init__(self, cols: int, rows: int, source_x: int, source_y: int = 0) -> None:
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
        self.source: Coord = (source_x, source_y)
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
        lines.append(f"  source chip is at {self.source}")
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

    def desired_chip_id(self, coord: Coord) -> int:
        x, y = coord
        desired = y * self.cols + x
        return PLACEHOLDER_CHIP_ID if desired == 1 else desired

    def prepare_source_row_path(self, target_x: int) -> None:
        if target_x == self.source_x:
            return
        step = 1 if target_x > self.source_x else -1
        lane = Lane.EAST if step > 0 else Lane.WEST
        lane_only = lane_mask(lane)
        direction = "east" if step > 0 else "west"

        source_id = self.chip(self.source).chip_id
        self.write_up(
            source_id,
            self.source,
            lane_only,
            f"source-row path prepare toward column {target_x} via {direction} from {self.source}",
            replace=True,
        )

        x = self.source_x + step
        while x != target_x:
            coord = (x, self.source_y)
            chip_id = self.chip(coord).chip_id
            self.write_up(
                chip_id,
                coord,
                lane_only,
                f"source-row relay prepare toward column {target_x} via {direction} for chip at {coord}",
                replace=True,
            )
            x += step

    def assign_source_row(self) -> None:
        source_id = self.desired_chip_id(self.source)
        self.write_chip_id(1, self.source, source_id, f"source assignment at {self.source}")
        self.write_down(source_id, self.source, SOUTH_ONLY, f"source south downstream keep for chip at {self.source}")

        if self.source_x < self.cols - 1:
            self.write_up(source_id, self.source, EAST_ONLY, f"source-row east prepare for chip at {self.source}", replace=True)
            for x in range(self.source_x, self.cols - 1):
                current = (x, self.source_y)
                target = (x + 1, self.source_y)
                current_id = self.chip(current).chip_id
                if x > self.source_x:
                    self.write_up(current_id, current, EAST_ONLY, f"source-row east-only propagation enable for chip at {current}", replace=True)
                target_id = self.desired_chip_id(target)
                self.write_chip_id(1, target, target_id, f"source-row assign east neighbor of chip at {current}")
                self.write_down(target_id, target, WEST_ONLY, f"source-row west downstream enable for chip at {target}")

        if self.source_x > 0:
            source_id = self.chip(self.source).chip_id
            self.write_up(source_id, self.source, WEST_ONLY, f"source-row west prepare for chip at {self.source}", replace=True)
            for x in range(self.source_x, 0, -1):
                current = (x, self.source_y)
                target = (x - 1, self.source_y)
                current_id = self.chip(current).chip_id
                if x < self.source_x:
                    self.write_up(current_id, current, WEST_ONLY, f"source-row west-only propagation enable for chip at {current}", replace=True)
                target_id = self.desired_chip_id(target)
                self.write_chip_id(1, target, target_id, f"source-row assign west neighbor of chip at {current}")
                self.write_down(target_id, target, EAST_ONLY, f"source-row east downstream enable for chip at {target}")

    def bootstrap_vertical_direction(self, col: int, lane: Lane) -> None:
        root = (col, self.source_y)
        lane_only = lane_mask(lane)
        opposite_only = lane_mask(opposite_lane(lane))
        step = 1 if lane == Lane.NORTH else -1
        direction = "north" if lane == Lane.NORTH else "south"

        if (lane == Lane.NORTH and self.source_y == self.rows - 1) or (lane == Lane.SOUTH and self.source_y == 0):
            return

        self.prepare_source_row_path(col)
        root_id = self.chip(root).chip_id
        self.write_up(root_id, root, lane_only, f"column {col} root prepare {direction} enable for chip at {root}", replace=True)

        y = self.source_y
        boundary = self.rows - 1 if lane == Lane.NORTH else 0
        while y != boundary:
            current = (col, y)
            target = (col, y + step)
            target_id = self.desired_chip_id(target)
            self.write_chip_id(1, target, target_id, f"column {col} assign {direction} neighbor of chip at {current}")
            self.write_down(target_id, target, opposite_only, f"column {col} downstream return enable for chip at {target}")
            if target[1] != boundary:
                self.write_up(target_id, target, lane_only, f"column {col} {direction}-only propagation enable for chip at {target}", replace=True)
            y += step

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

    def run_cleanup_remap(self) -> None:
        placeholder = None
        for coord in self.coords():
            if self.chip(coord).chip_id == PLACEHOLDER_CHIP_ID:
                placeholder = coord
                break
        if placeholder is None:
            return
        ones = [coord for coord in self.coords() if self.chip(coord).chip_id == 1]
        if ones:
            raise ProtocolError(f"cleanup remap: cannot rewrite placeholder while chip_id=1 still exists at {sorted(ones)}")
        self.unique_destination(PLACEHOLDER_CHIP_ID, placeholder, "cleanup remap route check")
        old = self.chip(placeholder).chip_id
        self.chip(placeholder).chip_id = 1
        self.logs.append(f"cleanup remap: chip at {placeholder} remapped chip_id {old} -> 1")

    def normalize_final_up_masks(self) -> None:
        row_order = [self.source_x]
        row_order.extend(range(self.source_x - 1, -1, -1))
        row_order.extend(range(self.source_x + 1, self.cols))
        for x in row_order:
            coord = (x, self.source_y)
            chip_id = self.chip(coord).chip_id
            self.write_up(chip_id, coord, self.final_source_row_up_mask(x), f"final source-row normalize for chip at {coord}", replace=True)

        for x in row_order:
            for y in range(self.source_y + 1, self.rows):
                coord = (x, y)
                chip_id = self.chip(coord).chip_id
                self.write_up(chip_id, coord, self.final_vertical_up_mask(y), f"final north-column normalize for chip at {coord}", replace=True)
            for y in range(self.source_y - 1, -1, -1):
                coord = (x, y)
                chip_id = self.chip(coord).chip_id
                self.write_up(chip_id, coord, self.final_vertical_up_mask(y), f"final south-column normalize for chip at {coord}", replace=True)

    def run(self) -> None:
        self.chip(self.source).down_mask = SOUTH_ONLY
        self.snapshot("Initial Configuration")

        self.assign_source_row()
        self.snapshot("After Source Row Assigned")

        for col in range(self.cols):
            self.bootstrap_vertical_direction(col, Lane.NORTH)
            self.bootstrap_vertical_direction(col, Lane.SOUTH)

        self.normalize_final_up_masks()
        self.run_cleanup_remap()
        self.snapshot("After Full Protocol Completed")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Simulate the chip-ID bootstrap protocol from the markdown")
    parser.add_argument("rows", type=int, help="number of rows")
    parser.add_argument("cols", type=int, help="number of columns")
    parser.add_argument("s", type=int, help="source chip x-position")
    parser.add_argument("--source-y", type=int, default=0, help="source chip y-position")
    parser.add_argument("--show-log", action="store_true", help="print the step-by-step protocol log")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    sim = BootstrapSim(args.cols, args.rows, args.s, args.source_y)
    try:
        sim.run()
        status = "PASS: protocol completed without broken, ambiguous, or wrong-target routing"
    except ProtocolError as exc:
        status = f"FAIL: {exc}"

    print(f"Bootstrap simulation for rows={args.rows}, cols={args.cols}, source=({args.s},{args.source_y})")
    print(status)
    print()

    order = [
        "Initial Configuration",
        "After Source Row Assigned",
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
