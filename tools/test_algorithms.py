#!/usr/bin/env python3
"""Niezmienniki algorytmow kopiera 6502 sprawdzane na komputerze gospodarza."""

from pathlib import Path
import hashlib
import re


def required_banks(total_sectors: int, bytes_per_sector: int) -> int:
    payload = min(total_sectors, 3) * 128
    payload += max(total_sectors - 3, 0) * bytes_per_sector
    return (payload + 16383) // 16384


def final_buffer_position(total_sectors: int, bytes_per_sector: int) -> tuple[int, int]:
    bank = 0
    offset = 0
    for sector in range(1, total_sectors + 1):
        length = 128 if sector <= 3 else bytes_per_sector
        for _ in range(length):
            offset += 1
            if offset == 16384:
                bank += 1
                offset = 0
    return bank, offset


def chunk_ranges(
    total_sectors: int, bytes_per_sector: int, banks: int
) -> list[tuple[int, int]]:
    capacity_units = banks * (16384 // 128)
    result: list[tuple[int, int]] = []
    start = 1
    while start <= total_sectors:
        used = 0
        end = start - 1
        for sector in range(start, total_sectors + 1):
            units = 1 if sector <= 3 else bytes_per_sector // 128
            if used + units > capacity_units:
                break
            used += units
            end = sector
        assert end >= start
        result.append((start, end))
        start = end + 1
    return result


def next_detected_drive(current: int, present: set[int]) -> int:
    """Hostowy odpowiednik petli 6502 wybierajacej tylko obecne Dn:."""
    candidate = current
    while True:
        candidate = 1 if candidate == 8 else candidate + 1
        if candidate in present:
            return candidate
        if candidate == current:
            return current


def hyperxf_track_valid(block: bytes, sectors_per_track: int) -> bool:
    """Hostowy odpowiednik walidatora tablicy sektorow komendy HyperXF $67."""
    seen: set[int] = set()
    for offset in range(12, 57):
        entry = block[offset]
        if entry == 0:
            return len(seen) == sectors_per_track
        if entry == 0xC0:
            continue
        status = entry & 0xE0
        number = entry & 0x1F
        if status not in (0x00, 0xE0):
            return False
        if not 1 <= number <= sectors_per_track or number in seen:
            return False
        seen.add(number)
    return False


def track_progress_cells(sector: int, sectors_per_track: int) -> int:
    """Liczba zapalonych pol 32-znakowego paska biezacej sciezki."""
    completed = (sector - 1) % sectors_per_track + 1
    return completed * 32 // sectors_per_track


def disk_progress_cell(sector: int, total_sectors: int) -> int:
    """Przyblizenie 32-polowego paska zgodne z tania petla 6502."""
    step = (total_sectors + 31) // 32
    return min((sector - 1) // step, 31)


def nominal_kb(total_sectors: int, bytes_per_sector: int) -> int:
    """Nominalna pojemnosc pokazywana w panelu wariantu A."""
    return total_sectors // {128: 8, 256: 4, 512: 2}[bytes_per_sector]


CASES = {
    "SD 90K": (720, 128, 6),
    "ED 130K": (1040, 128, 9),
    "DD 180K": (720, 256, 12),
    "HyperXF 5.25 SD 180K": (1440, 128, 12),
    "HyperXF 5.25 MD 260K": (2080, 128, 17),
    "HyperXF 5.25 DD 360K": (1440, 256, 23),
    "HyperXF 3.5 SD 360K": (2880, 128, 23),
    "HyperXF 3.5 MD 520K": (4160, 128, 33),
    "HyperXF 720K": (2880, 256, 45),
    "2880x512": (2880, 512, 90),
}

for name, (sectors, bps, expected) in CASES.items():
    actual = required_banks(sectors, bps)
    assert actual == expected, f"{name}: {actual} != {expected}"
    bank, offset = final_buffer_position(sectors, bps)
    occupied = bank + (offset != 0)
    payload = min(sectors, 3) * 128 + max(sectors - 3, 0) * bps
    logical_banks = (payload + 16383) // 16384
    assert occupied == logical_banks, (
        f"{name}: stream uses {occupied}, expected {logical_banks}"
    )

assert nominal_kb(720, 128) == 90
assert nominal_kb(1040, 128) == 130
assert nominal_kb(720, 256) == 180
assert nominal_kb(1440, 256) == 360
assert nominal_kb(2080, 128) == 260
assert nominal_kb(2880, 256) == 720
assert nominal_kb(4160, 128) == 520

assert len(chunk_ranges(720, 128, 1)) == 6
assert len(chunk_ranges(720, 256, 1)) == 12
assert len(chunk_ranges(2880, 256, 1)) == 45
assert chunk_ranges(2880, 256, 45) == [(1, 2880)]
assert len(chunk_ranges(2880, 256, 44)) == 2
assert len(chunk_ranges(2880, 512, 65)) == 2

assert next_detected_drive(1, {1, 3, 8}) == 3
assert next_detected_drive(3, {1, 3, 8}) == 8
assert next_detected_drive(8, {1, 3, 8}) == 1
assert next_detected_drive(6, {6}) == 6
assert next_detected_drive(4, set()) == 4

for spt in (18, 26):
    assert track_progress_cells(1, spt) == 32 // spt
    assert track_progress_cells(spt, spt) == 32
    assert track_progress_cells(spt + 1, spt) == 32 // spt
    assert all(
        1 <= track_progress_cells(sector + 1, spt)
        - track_progress_cells(sector, spt)
        <= 2
        for sector in range(1, spt)
    )
for total in (720, 1040, 1440, 2080, 2880, 4160):
    assert disk_progress_cell(1, total) == 0
    assert disk_progress_cell(total, total) == 31
    for start, _ in chunk_ranges(total, 256 if total in (720, 1440, 2880) else 128, 1):
        assert disk_progress_cell(start, total) == min(
            (start - 1) // ((total + 31) // 32), 31
        )

# $67 ma udowadniac kompletna sciezke, nie tylko udana transmisje 128 bajtow.
track18 = bytearray(128)
track18[12:32] = bytes((1, 13, 6, 0xC0, 18, 11, 4, 16, 9, 2, 14, 7, 12, 5, 17, 10, 3, 15, 8, 0))
assert hyperxf_track_valid(track18, 18)
track26 = bytearray(128)
track26[12:38] = bytes(0xE0 | number for number in range(1, 27))
assert hyperxf_track_valid(track26, 26)
bad_track = bytearray(track18)
bad_track[20] = bad_track[19]
assert not hyperxf_track_valid(bad_track, 18)
bad_track = bytearray(track18)
bad_track[20] = 19
assert not hyperxf_track_valid(bad_track, 18)
bad_track = bytearray(track18)
bad_track[20] |= 0x20
assert not hyperxf_track_valid(bad_track, 18)
bad_track = bytearray(track18)
bad_track[20] = 0
assert not hyperxf_track_valid(bad_track, 18)

# Ramka zajmuje kolumny 0 i 39, dlatego kazdy tekst ekranowy musi miescic sie
# w 38-kolumnowym obszarze pomiedzy nimi.
project_root = Path(__file__).parents[1]
main_source = (project_root / "src" / "main.s").read_text()
memory_source = (project_root / "src" / "memory.s").read_text()
version = (project_root / "VERSION").read_text().strip()
changelog = (project_root / "CHANGELOG.md").read_text()
assert f'SECTOR COPY U1 {version}' in main_source
assert f"## [{version}]" in changelog
for line_number, line in enumerate(main_source.splitlines(), 1):
    for literal in re.findall(r'"([^"]*)"', line):
        assert len(literal) <= 38, (
            f"main.s:{line_number}: {len(literal)} columns: {literal!r}"
        )

# Surowy podglad sektora odwzorowuje wszystkie 256 wartosci ATASCII, lacznie
# ze znakami sterujacymi, semigrafika i negatywem, na kody ekranowe GR.0.
def atascii_to_screen(value: int) -> int:
    if value < 0x20 or 0x80 <= value < 0xA0:
        return value + 0x40
    if 0x20 <= value < 0x60 or 0xA0 <= value < 0xE0:
        return value - 0x20
    return value


expected_boundaries = {
    0x00: 0x40,
    0x1F: 0x5F,
    0x20: 0x00,
    0x5F: 0x3F,
    0x60: 0x60,
    0x7F: 0x7F,
    0x80: 0xC0,
    0x9F: 0xDF,
    0xA0: 0x80,
    0xDF: 0xBF,
    0xE0: 0xE0,
    0xFF: 0xFF,
}
assert {value: atascii_to_screen(value) for value in expected_boundaries} == (
    expected_boundaries
)
assert ".proc render_sector_atascii" in main_source
assert "atascii_screen_table:" in main_source
assert "lda atascii_screen_table,x" in main_source
assert ".proc store_hex_screen" in main_source
assert "jsr ui_set_cursor\n    lda copy_current_hi" not in main_source
assert "PROGRESS_DATA_COL   = 4" in main_source
assert ".byte 4, 8, 16" in main_source

# Menu musi uzywac niebuforowanej procedury K: w IOCB #1, a nie wejscia
# wierszowego z kanalu E:. Stockowy glif $7C daje wycentrowany pion ramki
# juz na pierwszym ekranie i nie wymaga niszczacej kopii fontu pod $A000.
ui_source = (Path(__file__).parents[1] / "src" / "ui.s").read_text()
assert '.byte "K:", 0' in ui_source
assert "ldx #$10\n    lda #CIO_GETCHR" in ui_source
assert "sta ICCOM,x" in ui_source
assert "BOX_V  = $7C" in ui_source
assert "SCREEN_BOX_V        = $7C" in main_source
assert "ui_install_font" not in ui_source
assert "ui_install_font" not in main_source
assert "READ_BACKGROUND  = $C2" in ui_source
assert "WRITE_BACKGROUND = $32" in ui_source
assert "VERIFY_BACKGROUND = $12" in ui_source
assert ".proc ui_colors_read" in ui_source
assert ".proc ui_colors_write" in ui_source
assert ".proc ui_colors_verify" in ui_source
assert ".proc ui_get_key_upper" in ui_source
assert ".proc ui_wait_start_select" in ui_source
assert "lda CONSOL\n    and #$07" in ui_source
assert "cmp #$06" in ui_source and "cmp #$05" in ui_source

# Kazde pytanie o nosnik po odczycie zaczyna sie na czystym ekranie z ramka.
# Po zbuforowaniu pelnej porcji bledy celu, formatu, zapisu lub weryfikacji
# udostepniaja ponowny zapis bez kolejnego wywolania copy_read_all.
assert main_source.count("jsr begin_media_prompt") == 3
assert "read_disk:\n    jsr ui_begin_screen\n    jsr ui_colors_read" in main_source
assert "write_disk:\n    jsr ui_begin_screen\n    jsr ui_colors_write" in main_source
assert "jsr ui_colors_verify" in main_source
assert "target_retry_error:" in main_source
assert '"R-PONOW ZAPIS Z BUFORA"' in main_source
assert "retry_write:\n    lda #1\n    sta target_initialized\n    jmp write_disk" in main_source
retry_start = main_source.index("target_retry_error:")
retry_end = main_source.index('.segment "CODE"', retry_start)
assert "copy_read_all" not in main_source[retry_start:retry_end]
assert main_source.count("jmp target_retry_error") >= 6

# Pelny obraz jednoprzebiegowy pozostaje dostepny po zapisie i porownaniu.
# START zapisuje kolejny cel bez copy_read_all, a SELECT wraca. Przy wielu
# przebiegach opcja jest ukryta, bo bufor zawiera tylko ostatnia porcje.
success_start = main_source.index("success_wait:")
success_end = main_source.index("success_return:", success_start)
success_path = main_source[success_start:success_end]
assert "lda copy_single_pass" in success_path
assert "jsr ui_wait_start_select" in success_path
assert "jsr copy_begin_chunks" in success_path
assert "jmp check_preformatted" in success_path
assert "jmp format_target" in success_path
assert "copy_read_all" not in success_path

# Glowne menu ma dwa osobne panele stacji. Asercje obejmuja procedury wyboru,
# kluczowe etykiety oraz komplet skrotow klawiaturowych obu paneli.
assert f'title:\n    .byte "SECTOR COPY U1 {version}"' in main_source
assert '.byte "             Paptak 2026", 0' in main_source
assert ".proc draw_panel_box" in main_source
assert ".proc draw_selected_panel" in main_source
assert '.byte "POJEDYNCZA (SD)", 0' in main_source
assert '.byte "ROZSZERZ. (ED)", 0' in main_source
assert '.byte "PODWOJNA (DD)", 0' in main_source
assert '.byte "PODW. 2-STRONNA", 0' in main_source
assert '.byte "SIO STANDARD", 0' in main_source
assert '.byte "TURBO", 0' in main_source
for panel_line in (
    "POJEDYNCZA (SD)",
    "ROZSZERZ. (ED)",
    "PODWOJNA (DD)",
    "PODW. 2-STRONNA",
    "SEKTORY 512 B",
    "SIO STANDARD",
    "TURBO 1050/16",
    "26X128  4160 S",
):
    assert len(panel_line) <= 16, f"panel overflow: {panel_line!r}"
assert ".proc invert_copy_action" not in main_source
assert "source_panel_title:\n    .byte 'Z'|$80" in main_source
assert "target_panel_title:\n    .byte 'C'|$80" in main_source
assert "copy_action:\n    .byte 'K'|$80" in main_source
assert "verify_label:\n    .byte 'W'|$80" in main_source
assert "format_label:\n    .byte 'F'|$80" in main_source
for key in ("Z", "C", "K", "F", "W", "S", "P", "Q"):
    assert f"cmp #'{key}'" in main_source
assert "cmp #'T'" not in main_source
assert "cmp #'1'\n    beq next_source" not in main_source
assert "cmp #'2'\n    beq next_target" not in main_source
assert "drive_loop:" not in main_source
assert "SCAN_DRIVES = 8" in main_source
assert "cmp #$36\n    bcc clear_dos" in memory_source
assert "cmp #$37\n    bcc clear_dos" not in memory_source
assert "cmp #$38\n    bcc clear_dos" not in memory_source
assert '.byte "PRZEBIEG ", 0' in main_source
assert "PORCJA" not in main_source
assert '"POTWIERDZ ZAPIS NA DYSKU DOCELOWYM."' in main_source
assert main_source.count("ATASCII_ESC, $09") >= 4
assert main_source.count("ATASCII_ESC, $89") >= 4
assert "ldx #12\n    jsr ui_set_cursor\n    lda #<copy_action" in main_source
assert '.byte "---USTAWIENIA---", 0' in main_source
assert '.byte "PARAMETRY KOPII", 0' in main_source
assert '.byte "---NOSNIKI---", 0' in main_source
assert '.byte "---DANE I PAMIEC---", 0' in main_source
assert ".proc draw_wide_box" in main_source
assert "SIO: WLASNE / AUTO" not in main_source
assert ".proc do_test_read" not in main_source
for confirm_line in (
    "ZRODLO D1  720 KB  TURBO 1050/16",
    "CEL    D2  720 KB  TURBO HXF9",
    "GEOMETRIA   80X2X18 / 256 B",
    "BUFOR 16 KB 45/65",
):
    assert len(confirm_line) <= 34, f"confirmation overflow: {confirm_line!r}"
assert '.byte "SKAN D1-D8...", 0' in main_source
assert "SKAN ZAKONCZONY" not in main_source
assert ".proc next_detected_drive" in main_source
assert ".proc ensure_detected_drive" in main_source
assert "inc source_drive" not in main_source
assert "inc target_drive" not in main_source

# Stacja przyjmujaca SET PERCOM i FORMAT nie musi umiec zwrotnie podac nowej
# geometrii przez GET PERCOM. Udane formatowanie ustanawia geometrie zrodla;
# opcja FORMAT: NIE nadal wymaga jej jawnego sprawdzenia.
assert "jsr copy_format_target\n    bcc format_complete" in main_source
format_complete = main_source.index("format_complete:")
target_ready = main_source.index("target_ready:", format_complete)
assert "copy_validate_target" not in main_source[format_complete:target_ready]

buffer_source = (Path(__file__).parents[1] / "src" / "buffer.s").read_text()
copy_source = (Path(__file__).parents[1] / "src" / "copy.s").read_text()
assert "bad_source_geometry:" in copy_source
assert copy_source.count("bmi bad_geometry") >= 2
assert "lda sio_length_lo" in buffer_source
assert "lda sio_length_hi" in buffer_source
assert "lda DBYTLO" not in buffer_source
assert "lda DBYTHI" not in buffer_source
assert ".proc buffer_compare" in buffer_source
assert "copy_compare_buf" not in buffer_source
assert ".proc advance_block" in buffer_source
assert ".proc decrement_block" in buffer_source
assert "bpl copy_byte" in buffer_source
assert ".proc advance_data" not in buffer_source
assert ".proc decrement_length" not in buffer_source

# Wszystkie transfery musza przechodzic przez niezalezny sterownik POKEY.
# Wykrycie dzielnika przez $3F nie wystarcza, jesli operacje sektorowe uzywaja
# pozniej standardowego SIOV.
root = Path(__file__).parents[1]
sio_source = (root / "src" / "sio.s").read_text()
geometry_source = (root / "src" / "geometry.s").read_text()
blob_source = (root / "src" / "hsio_blob.s").read_text()
assert ".import hsio_auto" in sio_source
assert "jsr hsio_auto" in sio_source
assert "sta sio_actual_mode" in sio_source
assert "jsr SIOV" not in sio_source
assert "sio_get_hsi" not in sio_source
assert "ldx #7\n    lda #0\nloop:\n    sta hsio_speed_table,x" in sio_source
assert "MAX_DRIVES = 8" in geometry_source
assert copy_source.count("cmp #9") >= 2
assert "lda hsio_speed_table-1,x" in sio_source
assert ".proc geo_set_speed" in geometry_source
assert "cmp #$40\n    beq xf" in geometry_source
assert "cmp #$41\n    beq warp" in geometry_source
assert "cmp #$80\n    beq turbo" in geometry_source
assert "cmp #$D9" in main_source
assert 'hxf_label:\n    .byte " HXF", 0' in main_source
assert '"HYPERXF SKEW: ULTRASPEED"' in main_source
assert "jsr sio_status_force" in main_source
assert "jsr sio_hyperxf_track_info" in main_source
# Zgodnie z zachowaniem klasycznych DOS-ow i dokumentacja HyperXF, pierwszy
# READ sektora 1 ma poprzedzac STATUS, ktory dopiero wtedy raportuje gestosc
# aktualnie wlozonego nosnika.
probe_start = main_source.index(".proc probe_drive")
probe_end = main_source.index("probe_standard:", probe_start)
probe_prefix = main_source[probe_start:probe_end]
assert probe_prefix.index("jsr sio_read_boot_sector") < probe_prefix.index("jsr sio_status")
assert ".proc hyperxf_track_valid" in main_source
assert ".proc probe_hyperxf_track" in main_source
assert "cmp #$C0\n    beq advance_entry" in main_source
assert "hyperxf_ambiguous:" in main_source
assert "lda #$80\n    sta geo_present,x" in main_source
for track in (0, 39, 40, 79, 80, 159):
    assert f"ldx #{track}" in main_source
assert "lda #80\n    sta geo_tracks,x" in main_source
assert "sta copy_reading+17" in main_source
assert "sta copy_writing+17" in main_source
assert "PROGRESS_SPEED_COL  = 35" in main_source
assert "lda #PROGRESS_NUMBER_ROW\n    ldx #31" in main_source
assert "TRACK_BAR_OFFSET    = 3" in main_source
assert "DISK_BAR_OFFSET     = 43" in main_source
assert ".proc init_track_progress" in main_source
assert ".proc init_disk_progress" in main_source
assert ".proc update_disk_progress" in main_source
assert ".proc advance_track_progress" in main_source
assert "SCREEN_PROGRESS     = $54" in main_source
assert "adc #32\nnext_cell:" in main_source
assert "sta progress_track_pos\n    beq" not in main_source
assert "cmp progress_track_spt" in main_source
assert "cmp progress_disk_step" in main_source
assert ".proc sio_status_force" in sio_source
assert "lda #'U'\n    sta DAUX2" in sio_source
assert ".proc sio_hyperxf_track_info" in sio_source
assert "lda #'g'\n    sta DCOMND" in sio_source
assert "lda #$20\n    sta DAUX2" in sio_source
assert '.incbin "hsio-1.33-3985-max8.bin", 6, 901' in blob_source

hsio_image = (root / "src" / "hsio-1.33-3985-max8.bin").read_bytes()
assert len(hsio_image) == 907
assert hashlib.sha256(hsio_image).hexdigest() == (
    "7ba8de340671c1e886d8c04e6e0733cd2978a57a47a6229ecc38cdfcd11f1db3"
)

print(
    f"OK: {len(CASES)} geometry/buffer cases, HyperXF track-table validation, "
    "sector-length source, "
    "multi-pass chunking, full ATASCII screen conversion, centered sector "
    "grids, four stage palettes, clean media prompts, buffered-write retry, "
    "repeat copy from one-pass buffer, START/SELECT confirmation, instant K: "
    "input, inverse-letter menu B, HyperXF identity/skew diagnostics, "
    "block-fast buffer loops, own HSIO without SIOV, verified HSIO blob, "
    "eight-drive limit, track/disk progress bars, and 38-column UI literals"
)
