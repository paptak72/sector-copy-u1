#!/usr/bin/env python3
"""Tworzy deterministyczne obrazy ATR dla matrycy testowej."""

from __future__ import annotations

import argparse
import hashlib
import struct
from pathlib import Path


FORMATS = {
    "sd-720": (720, 128),
    "ed-1040": (1040, 128),
    "dd-720": (720, 256),
    "xf551-1440": (1440, 256),
    "hyperxf-525-sd-1440": (1440, 128),
    "hyperxf-525-md-2080": (2080, 128),
    "hyperxf-525-dd-1440": (1440, 256),
    "hyperxf-35-sd-2880": (2880, 128),
    "hyperxf-35-md-4160": (4160, 128),
    "hyperxf-35-dd-2880": (2880, 256),
    # Krotki alias tej samej geometrii 2880 x 256 B.
    "hyperxf-2880": (2880, 256),
}


def sector_length(sector: int, sector_size: int) -> int:
    if sector_size > 128 and sector <= 3:
        return 128
    return sector_size


def make_payload(sectors: int, sector_size: int, patterned: bool) -> bytes:
    payload = bytearray()
    for sector in range(1, sectors + 1):
        length = sector_length(sector, sector_size)
        if patterned:
            data = bytearray(
                ((sector * 37 + offset * 13 + (offset >> 3)) & 0xFF)
                for offset in range(length)
            )
            # Jednosektorowy zalazek startowy pozwala ROM-owi zakonczyc probe
            # uruchomienia obrazu zamontowanego jako D1:. Laduje sie pod $2000
            # i natychmiast wraca z procedury INIT pod $2006.
            if sector == 1:
                data[:7] = bytes((0x00, 0x01, 0x00, 0x20, 0x06, 0x20, 0x60))
            payload.extend(data)
        else:
            payload.extend(b"\x00" * length)
    return bytes(payload)


def atr_header(payload_size: int, sector_size: int) -> bytes:
    if payload_size % 16:
        raise ValueError("ATR payload must have a size divisible by 16")
    paragraphs = payload_size // 16
    if paragraphs > 0xFFFFFF:
        raise ValueError("ATR image is too large")
    header = bytearray(16)
    struct.pack_into("<HHH", header, 0, 0x0296, paragraphs & 0xFFFF, sector_size)
    header[6] = (paragraphs >> 16) & 0xFF
    return bytes(header)


def write_image(path: Path, sectors: int, sector_size: int, patterned: bool) -> str:
    payload = make_payload(sectors, sector_size, patterned)
    path.write_bytes(atr_header(len(payload), sector_size) + payload)
    return hashlib.sha256(payload).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("test-disks"),
        help="directory for generated ATR images",
    )
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    for name, (sectors, sector_size) in FORMATS.items():
        for role, patterned in (("source", True), ("target", False)):
            path = args.output_dir / f"{role}-{name}.atr"
            digest = write_image(path, sectors, sector_size, patterned)
            print(
                f"{path}: {sectors} sectors, {sector_size} B, "
                f"payload-sha256={digest}"
            )


if __name__ == "__main__":
    main()
