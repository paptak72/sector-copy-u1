#!/usr/bin/env python3
"""Small structural validator for Atari segmented XEX files."""

from __future__ import annotations

import pathlib
import struct
import sys


def read_word(data: bytes, offset: int) -> tuple[int, int]:
    if offset + 2 > len(data):
        raise ValueError("unexpected end of file")
    return struct.unpack_from("<H", data, offset)[0], offset + 2


def parse_xex(data: bytes) -> list[tuple[int, int, bytes]]:
    offset = 0
    marker, offset = read_word(data, offset)
    if marker != 0xFFFF:
        raise ValueError(f"missing $FFFF header, got ${marker:04X}")

    segments: list[tuple[int, int, bytes]] = []
    while offset < len(data):
        start, offset = read_word(data, offset)
        while start == 0xFFFF:
            start, offset = read_word(data, offset)
        end, offset = read_word(data, offset)
        if end < start:
            raise ValueError(f"invalid segment ${start:04X}-${end:04X}")
        size = end - start + 1
        if offset + size > len(data):
            raise ValueError(f"truncated segment ${start:04X}-${end:04X}")
        payload = data[offset : offset + size]
        offset += size
        segments.append((start, end, payload))
    return segments


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check_xex.py FILE.xex", file=sys.stderr)
        return 2

    path = pathlib.Path(sys.argv[1])
    segments = parse_xex(path.read_bytes())
    run_segments = [item for item in segments if item[0] <= 0x02E0 <= item[1]]
    if len(run_segments) != 1:
        raise ValueError("XEX must contain exactly one RUNAD segment")

    run_segment = run_segments[0]
    run_offset = 0x02E0 - run_segment[0]
    if run_offset + 2 > len(run_segment[2]):
        raise ValueError("RUNAD segment does not contain a complete address")
    run_address = struct.unpack_from("<H", run_segment[2], run_offset)[0]

    code_segments = [item for item in segments if item[0] >= 0x8000]
    if not code_segments:
        raise ValueError("no program segment at or above $8000")

    print(
        f"OK: {path} contains {len(segments)} segments; "
        f"RUNAD=${run_address:04X}; size={path.stat().st_size} bytes"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

