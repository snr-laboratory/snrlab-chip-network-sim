#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Tuple

THIS_DIR = Path(__file__).resolve().parent
REPO_ROOT = THIS_DIR.parents[2]
SCRIPTS_DIR = REPO_ROOT / "larpix_network_sim" / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from larpix_uart import decode_packet

FRAME_BITS = 66
PLACEHOLDER_CHIP_ID = 254
CHIP_ID_REG = 122
ENABLE_PISO_UP_REG = 124
ENABLE_PISO_DOWN_REG = 125

DIRS = {
    0: (0, 1),
    1: (1, 0),
    2: (0, -1),
    3: (-1, 0),
}


@dataclass
class Chip:
    chip_id: int = 1
    up_mask: int = 0
    down_mask: int = 0


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description='Convert a live bootstrap run log into visualizer playback JSON')
    ap.add_argument('--rows', type=int, required=True)
    ap.add_argument('--cols', type=int, required=True)
    ap.add_argument('--s', type=int, required=True)
    ap.add_argument('--startup-json', required=True)
    ap.add_argument('--run-log', required=True)
    ap.add_argument('--out', required=True)
    return ap.parse_args()


def make_grid(rows: int, cols: int, s: int):
    grid = [[Chip() for _ in range(cols)] for _ in range(rows)]
    grid[0][s].down_mask = 0x04
    return grid


def chip(grid, coord):
    x, y = coord
    return grid[y][x]


def coords(rows, cols):
    for y in range(rows):
        for x in range(cols):
            yield (x, y)


def neighbors_from_mask(coord, mask, rows, cols):
    x, y = coord
    out = []
    for bit, (dx, dy) in DIRS.items():
        if (mask >> bit) & 1:
            nx, ny = x + dx, y + dy
            if 0 <= nx < cols and 0 <= ny < rows:
                out.append((nx, ny))
    return out


def unique_reachable_destination(grid, rows, cols, source, dest_id):
    q = deque([source])
    seen = {source}
    matches = []
    while q:
        cur = q.popleft()
        c = chip(grid, cur)
        if c.chip_id == dest_id:
            matches.append(cur)
        for nxt in neighbors_from_mask(cur, c.up_mask, rows, cols):
            if nxt not in seen:
                seen.add(nxt)
                q.append(nxt)
    if len(matches) != 1:
        raise ValueError(f'destination chip_id {dest_id} not uniquely reachable, matches={matches}')
    return matches[0]


def shortest_up_path(grid, rows, cols, source, target):
    q = deque([source])
    prev = {source: None}
    while q:
        cur = q.popleft()
        if cur == target:
            break
        for nxt in neighbors_from_mask(cur, chip(grid, cur).up_mask, rows, cols):
            if nxt not in prev:
                prev[nxt] = cur
                q.append(nxt)
    if target not in prev:
        raise ValueError(f'no upstream path from {source} to {target}')
    path = []
    cur = target
    while cur is not None:
        path.append(cur)
        cur = prev[cur]
    return list(reversed(path))


def shortest_down_path(grid, rows, cols, source, target):
    q = deque([source])
    prev = {source: None}
    while q:
        cur = q.popleft()
        if cur == target:
            break
        for nxt in neighbors_from_mask(cur, chip(grid, cur).down_mask, rows, cols):
            if nxt not in prev:
                prev[nxt] = cur
                q.append(nxt)
    if target not in prev:
        raise ValueError(f'no downstream path from {source} to {target}')
    path = []
    cur = target
    while cur is not None:
        path.append(cur)
        cur = prev[cur]
    return list(reversed(path))


def parse_run_log(path: Path):
    tx_re = re.compile(r'transmitted frame at seq=(\d+)\s*:\s*(0x[0-9a-fA-F]+)(?: label=(.*))?$')
    rx_re = re.compile(r'received packet at seq=(\d+):\s*(0x[0-9a-fA-F]+)$')
    tx = []
    rx = []
    for line in path.read_text().splitlines():
        m = tx_re.search(line)
        if m:
            tx.append({'seq': int(m.group(1)), 'packet_word': m.group(2), 'label': m.group(3) or ''})
            continue
        m = rx_re.search(line)
        if m:
            rx.append({'seq': int(m.group(1)), 'packet_word': m.group(2)})
    return tx, rx


def packet_type_name(word_hex: str) -> str:
    dec = decode_packet(int(word_hex, 16)).decoded
    kind = dec.get('kind', '')
    if kind == 'config_write':
        return 'config_write'
    if kind == 'config_read':
        return 'config_read_request'
    if kind == 'data':
        return 'event_data'
    return 'packet'


def edge_name(a, b):
    dx = b[0] - a[0]
    dy = b[1] - a[1]
    for bit, (ex, ey) in DIRS.items():
        if (dx, dy) == (ex, ey):
            return ['north', 'east', 'south', 'west'][bit]
    raise ValueError(f'not neighbors: {a}->{b}')


def initial_chips(grid, rows, cols):
    out = []
    for x, y in coords(rows, cols):
        c = chip(grid, (x, y))
        out.append({'x': x, 'y': y, 'chip_id': c.chip_id, 'up_mask': c.up_mask, 'down_mask': c.down_mask})
    return out


def main() -> int:
    args = parse_args()
    source = (args.s, 0)
    startup = json.loads(Path(args.startup_json).read_text())
    frames = startup.get('frames', [])
    tx_log, rx_log = parse_run_log(Path(args.run_log))

    if len(tx_log) != len(frames):
        raise SystemExit(f'transmitted frame count mismatch: startup has {len(frames)}, log has {len(tx_log)}')

    grid = make_grid(args.rows, args.cols, args.s)
    playback = {
        'name': f'Live bootstrap {args.rows}x{args.cols} s={args.s}',
        'rows': args.rows,
        'cols': args.cols,
        'source': {'x': args.s, 'y': 0},
        'total_ticks': max([0] + [int(e['seq']) for e in tx_log] + [int(e['seq']) for e in rx_log]) + 50,
        'initial_chips': initial_chips(grid, args.rows, args.cols),
        'chip_updates': [],
        'packet_spans': [],
        'fpga_spans': [],
    }

    rx_index = 0
    for frame, tx_entry in zip(frames, tx_log):
        tick_start = int(frame['tick_start'])
        tx_end = int(tx_entry['seq'])
        dest_id = int(frame['chip_id'])
        decoded = decode_packet(int(tx_entry['packet_word'], 16)).decoded
        target = unique_reachable_destination(grid, args.rows, args.cols, source, dest_id)
        up_path = shortest_up_path(grid, args.rows, args.cols, source, target)

        for hop_i, (a, b) in enumerate(zip(up_path, up_path[1:])):
            start = tick_start + hop_i * FRAME_BITS
            end = start + FRAME_BITS
            playback['packet_spans'].append({
                'start_tick': start,
                'end_tick': end,
                'src': list(a),
                'dst': list(b),
                'packet_type': packet_type_name(tx_entry['packet_word']),
                'packet_word': tx_entry['packet_word'],
                'label': frame.get('label', ''),
            })

        playback['fpga_spans'].append({
            'start_tick': tick_start,
            'end_tick': tick_start + FRAME_BITS,
            'packet_type': packet_type_name(tx_entry['packet_word']),
            'packet_word': tx_entry['packet_word'],
            'label': frame.get('label', ''),
        })

        reg = decoded.get('register_addr')
        data = decoded.get('register_data')
        if frame['type'] == 'write' and reg is not None and data is not None:
            c = chip(grid, target)
            update = {
                'tick': tx_end,
                'x': target[0],
                'y': target[1],
                'register_addr': int(reg),
                'register_data': int(data),
                'label': frame.get('label', ''),
                'event': 'config_applied',
            }
            if reg == CHIP_ID_REG:
                c.chip_id = int(data)
                update['chip_id'] = c.chip_id
            elif reg == ENABLE_PISO_UP_REG:
                c.up_mask = int(data) & 0xF
                update['up_mask'] = c.up_mask
            elif reg == ENABLE_PISO_DOWN_REG:
                c.down_mask = int(data) & 0xF
                update['down_mask'] = c.down_mask
            playback['chip_updates'].append(update)

        if frame['type'] == 'read':
            if rx_index >= len(rx_log):
                raise SystemExit('missing readback packets in run log')
            rx_entry = rx_log[rx_index]
            rx_index += 1
            reply_end = int(rx_entry['seq'])
            down_path = shortest_down_path(grid, args.rows, args.cols, target, source)
            hops = list(zip(down_path, down_path[1:]))
            base_start = max(tx_end + 1, reply_end - len(hops) * FRAME_BITS)
            for hop_i, (a, b) in enumerate(hops):
                start = base_start + hop_i * FRAME_BITS
                end = start + FRAME_BITS
                playback['packet_spans'].append({
                    'start_tick': start,
                    'end_tick': end,
                    'src': list(a),
                    'dst': list(b),
                    'packet_type': 'config_read_reply',
                    'packet_word': rx_entry['packet_word'],
                    'label': frame.get('label', ''),
                })

    Path(args.out).write_text(json.dumps(playback, indent=2) + '\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
