#!/usr/bin/env python3
"""Sprawdza stale obszary pamieci Atari zapisane w mapie ld65."""

from __future__ import annotations

import pathlib
import re
import sys


SEGMENT_RE = re.compile(
    r"^(ZEROPAGE|AUXCODE|BSS|LOWCODE|HSIO|UICODE|SCRATCH|CODE|RODATA|DATA)\s+"
    r"([0-9A-F]{6})\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+",
    re.MULTILINE,
)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check_memory_map.py FILE.map", file=sys.stderr)
        return 2

    path = pathlib.Path(sys.argv[1])
    segments = {
        name: (int(start, 16), int(end, 16), int(size, 16))
        for name, start, end, size in SEGMENT_RE.findall(path.read_text())
    }

    for required in (
        "ZEROPAGE", "AUXCODE", "BSS", "LOWCODE", "HSIO", "UICODE",
        "SCRATCH", "CODE", "RODATA"
    ):
        if required not in segments:
            raise ValueError(f"missing {required} segment")

    zp_start, zp_end, _ = segments["ZEROPAGE"]
    aux_start, aux_end, _ = segments["AUXCODE"]
    bss_start, bss_end, _ = segments["BSS"]
    low_start, low_end, _ = segments["LOWCODE"]
    hsio_start, hsio_end, hsio_size = segments["HSIO"]
    uicode_start, uicode_end, _ = segments["UICODE"]
    scratch_start, scratch_end, scratch_size = segments["SCRATCH"]
    code_start, code_end, _ = segments["CODE"]
    rodata_start, rodata_end, _ = segments["RODATA"]

    assert zp_start == 0x0080 and zp_end <= 0x00FF
    assert aux_start == 0x3600 and aux_end <= 0x37FF
    assert bss_start == 0x3800 and bss_end < low_start
    assert low_start == 0x392C and low_end < 0x3985
    assert (hsio_start, hsio_end, hsio_size) == (0x3985, 0x3D09, 0x0385)
    assert uicode_start == 0x3D0A and uicode_end <= 0x3DFF
    assert (scratch_start, scratch_end, scratch_size) == (0x3E00, 0x3FFF, 0x0200)
    assert code_start == 0x8000 and code_end < rodata_start

    # Kod i dane moga zajmowac $8000-$9FFF, ale nie przekraczaja tradycyjnego
    # okna BASIC/kartridza od $A000. Przed ponownym otwarciem E: APPMHI wskazuje
    # pierwszy bajt za RODATA, wiec ui_init tworzy ekran ponad aplikacja.
    assert rodata_end < 0xA000

    headroom = 0xA000 - (rodata_end + 1)
    print(
        "OK: ZP/AUX/BSS/LOW/HSIO/UICODE/SCRATCH fixed; own HSIO active; "
        "$4000-$7FFF free for banked data; "
        f"application ends at ${rodata_end:04X} ({headroom} bytes headroom)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
