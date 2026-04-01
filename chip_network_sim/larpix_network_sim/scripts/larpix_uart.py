#!/usr/bin/env python3
"""Helpers for LArPix packet encoding/decoding and UART framing.

This script matches the current LArPix RTL assumptions in:
- larpix_v3b/src/uart_tx.sv
- larpix_v3b/src/uart_rx.sv
- larpix_v3b/src/comms_ctrl.sv
- larpix_v3b/src/larpix_constants.sv

Packet width is 64 bits total:
- bits [62:0]: payload
- bit  [63]: odd parity over payload bits [62:0]

UART framing is:
- 1 start bit = 0
- 64 packet bits, LSB first
- 1 stop bit = 1
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass, asdict
from typing import Iterable, List

WIDTH = 64
PAYLOAD_WIDTH = 63
MAGIC_NUMBER = 0x89504E47
GLOBAL_ID = 0xFF

DATA_OP = 0b01
CONFIG_WRITE_OP = 0b10
CONFIG_READ_OP = 0b11


@dataclass
class PacketFields:
    word: int
    payload: int
    parity: int
    packet_type: int
    chip_id: int
    channel_or_addr: int
    timestamp_or_magic_low: int
    adc_or_reg_data: int
    trigger_type: int
    status_nibble: int
    downstream: int
    odd_parity_ok: bool
    kind: str
    decoded: dict


@dataclass
class UartFrame:
    bits: List[int]

    def as_string(self) -> str:
        return "".join(str(b) for b in self.bits)

    def as_csv(self) -> str:
        return ",".join(str(b) for b in self.bits)


def mask(width: int) -> int:
    return (1 << width) - 1


def odd_parity_bit(payload63: int) -> int:
    payload63 &= mask(PAYLOAD_WIDTH)
    ones = payload63.bit_count()
    return 0 if (ones & 1) else 1


def attach_parity(payload63: int) -> int:
    payload63 &= mask(PAYLOAD_WIDTH)
    return payload63 | (odd_parity_bit(payload63) << 63)


def check_odd_parity(word: int) -> bool:
    word &= mask(WIDTH)
    return (word.bit_count() & 1) == 1


def build_data_packet(
    *,
    chip_id: int,
    channel_id: int,
    timestamp: int,
    adc: int,
    trigger_type: int = 0,
    status_nibble: int = 0,
    downstream: int = 1,
    cds_reset: int = 0,
    cds_flag: int = 0,
) -> int:
    payload = 0
    payload |= (DATA_OP & 0x3) << 0
    payload |= (chip_id & 0xFF) << 2
    payload |= (channel_id & 0x3F) << 10
    payload |= (timestamp & 0x0FFFFFFF) << 16
    payload |= (cds_reset & 0x1) << 44
    payload |= (cds_flag & 0x1) << 45
    payload |= (adc & 0x3FF) << 46
    payload |= (trigger_type & 0x3) << 56
    payload |= (status_nibble & 0xF) << 58
    payload |= (downstream & 0x1) << 62
    return attach_parity(payload)


def build_config_write_packet(*, chip_id: int, register_addr: int, register_data: int) -> int:
    payload = 0
    payload |= (CONFIG_WRITE_OP & 0x3) << 0
    payload |= (chip_id & 0xFF) << 2
    payload |= (register_addr & 0xFF) << 10
    payload |= (register_data & 0xFF) << 18
    payload |= (MAGIC_NUMBER & 0xFFFFFFFF) << 26
    return attach_parity(payload)


def build_config_read_packet(*, chip_id: int, register_addr: int, stats_nibble: int = 0) -> int:
    payload = 0
    payload |= (CONFIG_READ_OP & 0x3) << 0
    payload |= (chip_id & 0xFF) << 2
    payload |= (register_addr & 0xFF) << 10
    payload |= (MAGIC_NUMBER & 0xFFFFFFFF) << 26
    payload |= (stats_nibble & 0xF) << 58
    return attach_parity(payload)


def packet_to_uart_bits(word: int) -> UartFrame:
    word &= mask(WIDTH)
    bits = [0]
    bits.extend((word >> i) & 1 for i in range(WIDTH))
    bits.append(1)
    return UartFrame(bits)


def uart_bits_to_packet(bits: Iterable[int]) -> int:
    bits = [int(b) for b in bits]
    if len(bits) != WIDTH + 2:
        raise ValueError(f"expected {WIDTH + 2} UART bits, got {len(bits)}")
    if bits[0] != 0:
        raise ValueError("UART start bit must be 0")
    if bits[-1] != 1:
        raise ValueError("UART stop bit must be 1")
    word = 0
    for i, bit in enumerate(bits[1:1 + WIDTH]):
        if bit not in (0, 1):
            raise ValueError(f"UART bit {i} is not 0/1: {bit}")
        word |= (bit & 1) << i
    return word


def parse_bits_arg(raw: str) -> List[int]:
    raw = raw.strip()
    if not raw:
        return []
    if "," in raw:
        items = [x.strip() for x in raw.split(",") if x.strip()]
    else:
        items = list(raw)
    bits = [int(x) for x in items]
    for bit in bits:
        if bit not in (0, 1):
            raise ValueError("all UART bits must be 0 or 1")
    return bits


def decode_packet(word: int) -> PacketFields:
    word &= mask(WIDTH)
    payload = word & mask(PAYLOAD_WIDTH)
    parity = (word >> 63) & 1
    packet_type = payload & 0x3
    chip_id = (payload >> 2) & 0xFF
    channel_or_addr = (payload >> 10) & 0xFF
    timestamp_or_magic_low = (payload >> 16) & 0x0FFFFFFF
    adc_or_reg_data = (payload >> 46) & 0x3FF
    trigger_type = (payload >> 56) & 0x3
    status_nibble = (payload >> 58) & 0xF
    downstream = (payload >> 62) & 0x1
    odd_ok = check_odd_parity(word)

    if packet_type == DATA_OP:
        kind = "data"
        decoded = {
            "packet_type": packet_type,
            "chip_id": chip_id,
            "channel_id": (payload >> 10) & 0x3F,
            "timestamp": (payload >> 16) & 0x0FFFFFFF,
            "cds_reset": (payload >> 44) & 0x1,
            "cds_flag": (payload >> 45) & 0x1,
            "adc": (payload >> 46) & 0x3FF,
            "trigger_type": (payload >> 56) & 0x3,
            "status_nibble": status_nibble,
            "downstream": downstream,
        }
    elif packet_type in (CONFIG_WRITE_OP, CONFIG_READ_OP):
        kind = "config_write" if packet_type == CONFIG_WRITE_OP else "config_read"
        decoded = {
            "packet_type": packet_type,
            "chip_id": chip_id,
            "register_addr": (payload >> 10) & 0xFF,
            "register_data": (payload >> 18) & 0xFF,
            "magic": (payload >> 26) & 0xFFFFFFFF,
            "stats_nibble": status_nibble,
            "downstream": downstream,
            "magic_ok": ((payload >> 26) & 0xFFFFFFFF) == MAGIC_NUMBER,
        }
    else:
        kind = "unknown"
        decoded = {
            "packet_type": packet_type,
            "chip_id": chip_id,
            "raw_payload": payload,
            "downstream": downstream,
        }

    return PacketFields(
        word=word,
        payload=payload,
        parity=parity,
        packet_type=packet_type,
        chip_id=chip_id,
        channel_or_addr=channel_or_addr,
        timestamp_or_magic_low=timestamp_or_magic_low,
        adc_or_reg_data=adc_or_reg_data,
        trigger_type=trigger_type,
        status_nibble=status_nibble,
        downstream=downstream,
        odd_parity_ok=odd_ok,
        kind=kind,
        decoded=decoded,
    )


def run_self_test() -> None:
    w_write = build_config_write_packet(chip_id=1, register_addr=125, register_data=1)
    d_write = decode_packet(w_write)
    assert d_write.kind == "config_write"
    assert d_write.decoded["register_addr"] == 125
    assert d_write.decoded["register_data"] == 1
    assert d_write.decoded["magic_ok"]
    assert d_write.odd_parity_ok

    w_read = build_config_read_packet(chip_id=1, register_addr=64)
    d_read = decode_packet(w_read)
    assert d_read.kind == "config_read"
    assert d_read.decoded["register_addr"] == 64
    assert d_read.decoded["magic_ok"]
    assert d_read.odd_parity_ok

    w_data = build_data_packet(chip_id=1, channel_id=7, timestamp=0x1234567, adc=399, trigger_type=0, status_nibble=0, downstream=1)
    d_data = decode_packet(w_data)
    assert d_data.kind == "data"
    assert d_data.decoded["channel_id"] == 7
    assert d_data.decoded["adc"] == 399
    assert d_data.odd_parity_ok

    frame = packet_to_uart_bits(w_data)
    assert len(frame.bits) == 66
    assert uart_bits_to_packet(frame.bits) == w_data


def add_common_output_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--json", action="store_true", help="emit JSON output")


def emit(obj, as_json: bool) -> None:
    if as_json:
        print(json.dumps(obj, indent=2, sort_keys=True))
    else:
        if isinstance(obj, str):
            print(obj)
        elif isinstance(obj, dict):
            for k, v in obj.items():
                print(f"{k}={v}")
        else:
            print(obj)


def main() -> int:
    parser = argparse.ArgumentParser(description="LArPix packet/UART helper")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("encode-write", help="build CONFIG_WRITE packet")
    p.add_argument("--chip", type=int, required=True)
    p.add_argument("--addr", type=int, required=True)
    p.add_argument("--data", type=int, required=True)
    p.add_argument("--uart-bits", action="store_true", help="print UART frame instead of packet word")
    p.add_argument("--csv", action="store_true", help="with --uart-bits, emit comma-separated bits")

    p = sub.add_parser("encode-read", help="build CONFIG_READ packet")
    p.add_argument("--chip", type=int, required=True)
    p.add_argument("--addr", type=int, required=True)
    p.add_argument("--stats", type=int, default=0)
    p.add_argument("--uart-bits", action="store_true", help="print UART frame instead of packet word")
    p.add_argument("--csv", action="store_true", help="with --uart-bits, emit comma-separated bits")

    p = sub.add_parser("encode-data", help="build DATA packet")
    p.add_argument("--chip", type=int, required=True)
    p.add_argument("--channel", type=int, required=True)
    p.add_argument("--timestamp", type=lambda s: int(s, 0), required=True)
    p.add_argument("--adc", type=int, required=True)
    p.add_argument("--trigger", type=int, default=0)
    p.add_argument("--status", type=int, default=0)
    p.add_argument("--downstream", type=int, default=1)
    p.add_argument("--cds-reset", type=int, default=0)
    p.add_argument("--cds-flag", type=int, default=0)
    p.add_argument("--uart-bits", action="store_true", help="print UART frame instead of packet word")
    p.add_argument("--csv", action="store_true", help="with --uart-bits, emit comma-separated bits")

    p = sub.add_parser("decode-word", help="decode a 64-bit packet word")
    p.add_argument("word", type=lambda s: int(s, 0))
    add_common_output_args(p)

    p = sub.add_parser("decode-uart", help="decode a 66-bit UART frame")
    p.add_argument("bits", help="UART bits as 001... or 0,0,1,...")
    add_common_output_args(p)

    sub.add_parser("self-test", help="run internal helper checks")

    args = parser.parse_args()

    if args.cmd == "encode-write":
        word = build_config_write_packet(chip_id=args.chip, register_addr=args.addr, register_data=args.data)
        if args.uart_bits:
            frame = packet_to_uart_bits(word)
            print(frame.as_csv() if args.csv else frame.as_string())
        else:
            print(hex(word))
        return 0

    if args.cmd == "encode-read":
        word = build_config_read_packet(chip_id=args.chip, register_addr=args.addr, stats_nibble=args.stats)
        if args.uart_bits:
            frame = packet_to_uart_bits(word)
            print(frame.as_csv() if args.csv else frame.as_string())
        else:
            print(hex(word))
        return 0

    if args.cmd == "encode-data":
        word = build_data_packet(
            chip_id=args.chip,
            channel_id=args.channel,
            timestamp=args.timestamp,
            adc=args.adc,
            trigger_type=args.trigger,
            status_nibble=args.status,
            downstream=args.downstream,
            cds_reset=args.cds_reset,
            cds_flag=args.cds_flag,
        )
        if args.uart_bits:
            frame = packet_to_uart_bits(word)
            print(frame.as_csv() if args.csv else frame.as_string())
        else:
            print(hex(word))
        return 0

    if args.cmd == "decode-word":
        decoded = decode_packet(args.word)
        obj = {
            "word_hex": hex(decoded.word),
            "payload_hex": hex(decoded.payload),
            "parity": decoded.parity,
            "odd_parity_ok": decoded.odd_parity_ok,
            "kind": decoded.kind,
            **decoded.decoded,
        }
        emit(obj, args.json)
        return 0

    if args.cmd == "decode-uart":
        bits = parse_bits_arg(args.bits)
        word = uart_bits_to_packet(bits)
        decoded = decode_packet(word)
        obj = {
            "word_hex": hex(decoded.word),
            "payload_hex": hex(decoded.payload),
            "parity": decoded.parity,
            "odd_parity_ok": decoded.odd_parity_ok,
            "kind": decoded.kind,
            **decoded.decoded,
        }
        emit(obj, args.json)
        return 0

    if args.cmd == "self-test":
        run_self_test()
        print("PASS: larpix_uart helper self-test")
        return 0

    parser.error("unknown command")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
