#!/usr/bin/env python3
"""Simulate the chip-ID bootstrap protocol using TX lane masks.

This is done entirely in software and serves only as test of a series of configuration writes which could be used to set chip_id for a network of chips from the initial state set by the RTL. In future, a similar protocol will be implemented in the network of chips simulated using the larpix_network_sim architecture and nng messaging both to prepare for future configuration and as a first test of configuration packet messaging. 


This script models the bootstrap protocol described in
`larpix_network_sim/CHIP_ID_BOOTSTRAP_SCRIPT_PLAN.md` using:
- chip IDs
- TX lane masks only
- packet delivery from the external controller into the source chip
- forwarding over enabled TX lanes
- local consumption when a packet reaches a chip whose ID matches the packet
  destination chip ID

The simulator catches three important error classes:
- broken routes: no chip with the destination ID is reachable
- ambiguous routes: more than one chip with the destination ID is reachable
- wrong-target routes: exactly one destination chip is reachable, but it is not
  the intended chip for that bootstrap step

It prints ASCII snapshots after these milestones when reached:
- initial configuration
- after bottom row assigned
- after first column assigned
- after full protocol completed
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
    tx_mask: int = 0x00


Grid = List[List[Chip]]
Coord = Tuple[int, int]


def lane_mask(*lanes: Lane) -> int:
    value = 0
    for lane in lanes:
        value |= 1 << int(lane)
    return value


NORTH_ONLY = lane_mask(Lane.NORTH)  # 0x01
EAST_ONLY = lane_mask(Lane.EAST)    # 0x02
WEST_ONLY = lane_mask(Lane.WEST)    # 0x08
NORTH_WEST = lane_mask(Lane.NORTH, Lane.WEST)          # 0x09
NORTH_EAST = lane_mask(Lane.NORTH, Lane.EAST)          # 0x03
NORTH_EAST_WEST = lane_mask(Lane.NORTH, Lane.EAST, Lane.WEST)  # 0x0B


class ProtocolError(RuntimeError):
    pass


class BootstrapSim:
    def __init__(self, m: int, n: int, s: int) -> None:
        if m <= 0 or n <= 0:
            raise ValueError("m and n must be positive")
        if not (0 <= s < m):
            raise ValueError("s must satisfy 0 <= s < m because the source chip is on the bottom row")

        self.m = m
        self.n = n
        self.s = s
        self.grid: Grid = [[Chip() for _ in range(m)] for _ in range(n)]
        self.source: Coord = (s, 0)
        self.snapshots: Dict[str, str] = {}
        self.logs: List[str] = []

    def chip(self, coord: Coord) -> Chip:
        x, y = coord
        return self.grid[y][x]

    def coords(self) -> Iterable[Coord]:
        for y in range(self.n):
            for x in range(self.m):
                yield (x, y)

    def snapshot(self, title: str) -> None:
        self.snapshots[title] = self.render_grid(title)

    def render_grid(self, title: str) -> str:
        max_id = max(self.chip(c).chip_id for c in self.coords())
        cell_w = max(7, len(str(max_id)) + 4)

        def hline() -> str:
            return "+" + "+".join("-" * (cell_w + 2) for _ in range(self.m)) + "+"

        lines = [title, hline()]
        for y in range(self.n - 1, -1, -1):
            vals = []
            for x in range(self.m):
                c = self.grid[y][x]
                vals.append(f"{c.chip_id}@{c.tx_mask & 0xF:04b}")
            row = "| " + " | ".join(f"{v:>{cell_w}}" for v in vals) + " |"
            lines.append(row)
            lines.append(hline())
        lines.append("  " + "   ".join(f"x={x}" for x in range(self.m)))
        lines.append("  top row is y={}".format(self.n - 1))
        lines.append("  bottom row is y=0")
        lines.append("  cell format = chip_id@TXMASKBIN")
        return "\n".join(lines)

    def neighbors_from_mask(self, coord: Coord, tx_mask: int) -> Iterable[Coord]:
        x, y = coord
        for lane, (dx, dy) in DIRS.items():
            if tx_mask & (1 << int(lane)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < self.m and 0 <= ny < self.n:
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

            for nxt in self.neighbors_from_mask(coord, chip.tx_mask):
                q.append(nxt)

        return consumers

    def unique_destination(self, dest_id: int, expected: Coord, context: str) -> Coord:
        consumers = self.reachable_destinations(dest_id)
        if len(consumers) == 0:
            raise ProtocolError(f"{context}: broken route, no reachable chip with destination chip_id={dest_id}")
        if len(consumers) > 1:
            coords = sorted(consumers)
            raise ProtocolError(
                f"{context}: ambiguous route, multiple reachable chips with destination chip_id={dest_id}: {coords}"
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
        self.logs.append(
            f"{context}: CHIP_ID write delivered to {coord}, chip_id {old} -> {new_chip_id}"
        )

    def write_tx_mask(self, dest_id: int, expected: Coord, new_mask: int, context: str) -> None:
        coord = self.unique_destination(dest_id, expected, context)
        old = self.chip(coord).tx_mask
        self.chip(coord).tx_mask = new_mask
        self.logs.append(
            f"{context}: ENABLE_PISO_DOWN write delivered to {coord}, tx_mask 0x{old:02X} -> 0x{new_mask:02X}"
        )

    def bootstrap_bottom_row_id(self, desired_chip_id: int) -> int:
        # Keep chip_id=1 reserved as the bootstrap target for still-unassigned chips.
        return 99 if desired_chip_id == 1 else desired_chip_id

    def run(self) -> None:
        self.snapshot("Initial Configuration")

        self.run_bottom_row()
        self.snapshot("After Bottom Row Assigned")

        self.run_first_column()
        self.snapshot("After First Column Assigned")

        self.run_remaining_columns()
        self.run_cleanup_remap()
        self.snapshot("After Full Protocol Completed")

    def run_bottom_row(self) -> None:
        # First configuration packet: source default ID 1 -> chip ID s, except that
        # bottom-row assignments to chip_id=1 are overridden to 99 to preserve 1 as
        # the bootstrap target for still-unassigned chips.
        source_id = self.bootstrap_bottom_row_id(self.s)
        self.write_chip_id(1, self.source, source_id, f"bottom-row source assignment (s={self.s})")

        # Eastward from source.
        for k in range(self.s, self.m - 1):
            current = (k, 0)
            target = (k + 1, 0)
            current_id = self.chip(current).chip_id
            target_id = self.bootstrap_bottom_row_id(k + 1)
            self.write_tx_mask(current_id, current, EAST_ONLY, f"bottom-row east enable for chip at {current}")
            self.write_chip_id(1, target, target_id, f"bottom-row assign east neighbor of chip at {current}")

        # Westward from source.
        for k in range(self.s, 0, -1):
            current = (k, 0)
            target = (k - 1, 0)
            current_id = self.chip(current).chip_id
            target_id = self.bootstrap_bottom_row_id(k - 1)
            self.write_tx_mask(current_id, current, WEST_ONLY, f"bottom-row west enable for chip at {current}")
            self.write_chip_id(1, target, target_id, f"bottom-row assign west neighbor of chip at {current}")

    def run_first_column(self) -> None:
        y = 0
        while y + 1 < self.n:
            current = (0, y)
            target = (0, y + 1)
            current_id = self.chip(current).chip_id
            next_id = (y + 1) * self.m
            self.write_tx_mask(current_id, current, NORTH_ONLY, f"first-column north enable for chip at {current}")
            self.write_chip_id(1, target, next_id, f"first-column assign north neighbor of chip at {current}")
            y += 1

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
        bottom = (c, 0)
        bottom_id = self.chip(bottom).chip_id
        self.write_tx_mask(bottom_id, bottom, self.bottom_cell_mask_for_column(c), f"column {c} bottom-cell prepare")

        y = 0
        while y + 1 < self.n:
            current = (c, y)
            target = (c, y + 1)
            current_id = self.chip(current).chip_id
            next_id = (y + 1) * self.m + c
            self.write_chip_id(1, target, next_id, f"column {c} assign north neighbor of chip at {current}")
            y += 1
            if y + 1 < self.n:
                current = (c, y)
                current_id = self.chip(current).chip_id
                self.write_tx_mask(current_id, current, NORTH_ONLY, f"column {c} north-only enable for chip at {current}")

    def run_remaining_columns(self) -> None:
        for c in range(1, self.m):
            self.run_column_from_bottom(c)

    def run_cleanup_remap(self) -> None:
        # Final cleanup step: once no still-unassigned chip_id=1 remains, remap the
        # temporary bootstrap placeholder chip_id=99 back to its intended final ID 1.
        placeholder = None
        ones = []
        for coord in self.coords():
            chip = self.chip(coord)
            if chip.chip_id == 99:
                placeholder = coord
            elif chip.chip_id == 1:
                ones.append(coord)

        if placeholder is None:
            return
        if ones:
            raise ProtocolError(
                f"cleanup remap: cannot rewrite placeholder chip_id=99 while chip_id=1 still exists at {sorted(ones)}"
            )

        old = self.chip(placeholder).chip_id
        self.chip(placeholder).chip_id = 1
        self.logs.append(
            f"cleanup remap: chip at {placeholder} remapped chip_id {old} -> 1"
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Simulate the TX-mask-aware chip-ID bootstrap protocol")
    parser.add_argument("m", type=int, help="number of columns")
    parser.add_argument("n", type=int, help="number of rows")
    parser.add_argument("s", type=int, help="source chip ID / x-position on bottom row")
    parser.add_argument("--show-log", action="store_true", help="print the step-by-step protocol log")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    sim = BootstrapSim(args.m, args.n, args.s)
    try:
        sim.run()
        status = "PASS: protocol completed without broken, ambiguous, or wrong-target routing"
    except ProtocolError as exc:
        status = f"FAIL: {exc}"

    print(f"Bootstrap TX-mask-aware simulation for m={args.m}, n={args.n}, s={args.s}")
    print(status)
    print()

    order = [
        "Initial Configuration",
        "After Bottom Row Assigned",
        "After First Column Assigned",
        "After Full Protocol Completed",
    ]
    for idx, title in enumerate(order):
        if idx:
            print()
        if title in sim.snapshots:
            print(sim.snapshots[title])
        else:
            print(title)
            print("<milestone not reached>")

    if args.show_log:
        print()
        print("Step Log")
        for line in sim.logs:
            print(f"- {line}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
