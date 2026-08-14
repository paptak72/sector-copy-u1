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


def preview_cells(length: int, data_row: int) -> list[int]:
    """Adresy ekranu przy lustrze 32 bajty danych -> wiersz 40 kolumn."""
    return [data_row * 40 + 4 + (i // 32) * 40 + i % 32 for i in range(length)]


def percom_density_agrees(status: int, sectors_per_track: int, bps: int) -> bool:
    """Model rozjemcy: świeży STATUS ma pierwszeństwo przed starym PERCOM."""
    # MyDOS i QMEG sprawdzaja najpierw bit 5. To celowo klasyfikuje $A0 jako
    # DD: ustawiony jednoczesnie bit 7 nie moze zmienic sektora 256 B na ED.
    if status & 0x20:
        return bps in (256, 512)
    if status & 0x80:
        return bps == 128 and sectors_per_track == 26
    return bps == 128 and sectors_per_track != 26


def xf551_status_sequence(media: str) -> tuple[int, int, int]:
    """Minimalny model przejscia ROM-u XF551 przez READ 1 i READ 4/256."""
    if media == "SD":
        return 0x00, 0x8A, 0x00
    if media == "ED":
        return 0x80, 0x8A, 0x80
    if media == "DD":
        # READ 1 pozostawia przejsciowe ED; sektor 4 wlacza DD i daje sukces.
        return 0x80, 0x01, 0x60
    raise ValueError(media)


def detected_extended_banks(physical_bank) -> int:
    """Model dwufazowej sondy PORTB: ostatnia sygnatura wygrywa na aliasie."""
    last_signature: dict[object, int] = {}
    for selector in range(64):
        last_signature[physical_bank(selector)] = selector
    main_signature = last_signature.get("main")
    return sum(
        last_signature[physical_bank(selector)] == selector
        and last_signature[physical_bank(selector)] != main_signature
        for selector in range(64)
    )


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

# Wszystkie kierunki sprzeczności, w tym zgłoszony na sprzęcie DD -> ED.
assert percom_density_agrees(0x00, 18, 128)
assert not percom_density_agrees(0x00, 26, 128)
assert not percom_density_agrees(0x00, 18, 256)
assert percom_density_agrees(0x80, 26, 128)
assert not percom_density_agrees(0x80, 18, 128)
assert not percom_density_agrees(0x80, 18, 256)
assert percom_density_agrees(0x20, 18, 256)
assert percom_density_agrees(0x20, 9, 512)
assert not percom_density_agrees(0x20, 26, 128)
assert percom_density_agrees(0x60, 18, 256)
assert not percom_density_agrees(0x60, 26, 128)
assert not percom_density_agrees(0xA0, 26, 128)
assert percom_density_agrees(0xA0, 18, 256)

# READ 4 jest wykonywany dla rozpoznanej rodziny XF niezaleznie od pierwszych
# bitow gestosci. SD/ED moga zakonczyc sama probe timeoutem, lecz rozstrzyga
# zawsze kolejny STATUS; fizyczny DD musi przejsc z $80 do $60.
assert xf551_status_sequence("SD") == (0x00, 0x8A, 0x00)
assert xf551_status_sequence("ED") == (0x80, 0x8A, 0x80)
assert xf551_status_sequence("DD") == (0x80, 0x01, 0x60)

assert nominal_kb(720, 128) == 90
assert nominal_kb(1040, 128) == 130
assert nominal_kb(720, 256) == 180

# Wnetrze podgladu zajmuje zawsze kolumny 4..35. Ramka jest w kolumnach
# 3 i 36, wiec nawet najwiekszy sektor nie moze jej nadpisac.
for length, data_row, rows in ((128, 9, 4), (256, 7, 8), (512, 4, 16)):
    cells = preview_cells(length, data_row)
    assert len(cells) == 32 * rows
    assert {cell % 40 for cell in cells} == set(range(4, 36))
    assert min(cell // 40 for cell in cells) == data_row
    assert max(cell // 40 for cell in cells) == data_row + rows - 1
    assert all(cell % 40 not in (0, 3, 36, 39) for cell in cells)
assert nominal_kb(1440, 256) == 360
assert nominal_kb(2080, 128) == 260
assert nominal_kb(2880, 256) == 720
assert nominal_kb(4160, 128) == 520

# Na maszynie 64K wszystkie selektory sa aliasem RAM-u glownego i musza zostac
# odrzucone. Klasyczny 130XE daje cztery banki przez bity 2-3 PORTB, a U1MB
# 1088K pelne 64 unikalne kombinacje. Chroni to przed wynikiem 80 KB na 64K.
assert detected_extended_banks(lambda _selector: "main") == 0
assert detected_extended_banks(lambda selector: ("xe", (selector >> 1) & 3)) == 4
assert detected_extended_banks(lambda selector: ("u1mb", selector)) == 64

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

# Zwykle READ/PUT wykorzystuje scratch $3E00. Obowiazkowa petla przenoszaca
# dane do/z banku jednoczesnie kopiuje surowe bajty do wycentrowanego okna
# szerokosci 32, bez osobnej konwersji. Wysokosci 4/8/16 odpowiadaja dokladnie
# 128/256/512 bajtom i nie pozwalaja danym wejsc na ramke semigraficzna.
assert ".proc render_sector_atascii" not in main_source
assert ".proc restore_sector_frame" not in main_source
assert ".proc copy_ui_prepare_data" in main_source
assert ".proc draw_sector_window" in main_source
assert ".proc store_hex_screen" in main_source
assert "jsr ui_set_cursor\n    lda copy_current_hi" not in main_source
assert ".byte 4, 8, 16" in main_source
assert ".byte <(9*40+4), <(7*40+4), <(4*40+4)" in main_source
assert "lda #33\n    sta scan_index" in main_source

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

# Glowne menu tworzy jeden zintegrowany pulpit z dwoma polami stacji. Asercje
# obejmuja ciagle polaczenia semigraficzne, procedury wyboru, kluczowe etykiety
# oraz komplet skrotow klawiaturowych obu paneli.
assert f'title:\n    .byte "SECTOR COPY U1 {version}"' in main_source
assert '.byte "             Paptak 2026", 0' in main_source
launch_start = main_source.index(".proc choose_launch_mode")
launch_end = main_source.index(".proc scan_all", launch_start)
launch_block = main_source[launch_start:launch_end]
launch_title_print = launch_block.index("lda #<title")
launch_eol = launch_block.index("jsr ui_print_eol", launch_title_print)
launch_separator = launch_block.index("jsr print_separator", launch_eol)
assert launch_title_print < launch_eol < launch_separator
assert ".proc draw_main_structure" in main_source
assert ".proc draw_selected_panel" in main_source
for semigraphic in (
    "SCREEN_T_LEFT       = $41",
    "SCREEN_T_RIGHT      = $44",
    "SCREEN_CROSS        = $53",
    "SCREEN_T_TOP        = $57",
    "SCREEN_T_BOTTOM     = $58",
):
    assert semigraphic in main_source
for separator in ("2*40", "4*40", "10*40", "12*40", "14*40", "20*40"):
    assert separator in main_source
assert "lda #39\n    sta scan_index" in main_source
assert "cpy scan_index" in main_source
assert "lda #35\n    sta scan_index" in main_source
assert ".proc screen_next_row" in main_source
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
assert "copy_action:\n    .byte \" \", 'K'|$80" in main_source
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
assert ".proc memory_prepare_main_ram" in memory_source
assert "lda #MAIN_PORTB\n    sta PORTB" in memory_source
assert "lda #$C0\n    sta RAMTOP" in memory_source
assert "lda RAMTOP\n    sta saved_ramtop" in memory_source
assert "lda saved_ramtop\n    sta RAMTOP" in memory_source
assert "jsr memory_prepare_main_ram\n    jsr memory_reserve_application" in main_source
assert '.byte "PRZEBIEG ", 0' in main_source
assert "PORCJA" not in main_source
assert '"POTWIERDZ ZAPIS NA DYSKU DOCELOWYM."' in main_source
assert main_source.count("ATASCII_ESC, $08") >= 4
assert main_source.count("ATASCII_ESC, $88") >= 4
assert "ATASCII_ESC, $09" not in main_source
assert "ATASCII_ESC, $89" not in main_source
assert "ldx #11\n    jsr ui_set_cursor\n    lda #<copy_action" in main_source
assert '.byte " USTAWIENIA ", 0' in main_source
assert '.byte "PARAMETRY KOPII", 0' in main_source
assert '.byte "---NOSNIKI---", 0' in main_source
assert '.byte "---DANE I PAMIEC---", 0' in main_source
assert ".proc draw_wide_box" in main_source
assert "SIO: WLASNE / AUTO" not in main_source
assert ".proc do_test_read" not in main_source
assert "DOS / LOADER" not in main_source
assert "SAMODZIELNY XEX" not in main_source
assert '.byte "BUFOR RAZEM: ", 0' in main_source
assert "lda mem_usable_banks\n    sta progress_src_ptr" in main_source
for confirm_line in (
    "ZRODLO D1  720 KB  TURBO 1050/16",
    "CEL    D2  720 KB  TURBO HXF9",
    "GEOMETRIA   80X2X18 / 256 B",
    "BUFOR 16 KB 45/65",
):
    assert len(confirm_line) <= 34, f"confirmation overflow: {confirm_line!r}"
assert '.byte "SKAN D1-D8", 0' in main_source
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
assert "lda #<sio_sector_buf\n    sta buffer_data_ptr" in buffer_source
assert "lda #>sio_sector_buf\n    sta buffer_data_ptr+1" in buffer_source
assert "copy_compare_buf" not in buffer_source
assert ".proc advance_block" in buffer_source
assert ".proc decrement_block" in buffer_source
assert buffer_source.count("sta (progress_dst_ptr),y") == 3
assert buffer_source.count("cpy #32") == 3
assert "adc #40\n    sta progress_dst_ptr" in buffer_source
assert "sbc #32" in buffer_source
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
assert ".proc sio_prepare_sector_buffer" not in sio_source
sector_dcb = sio_source.split(".proc sio_set_sector_dcb", 1)[1].split(
    ".endproc", 1
)[0]
assert "lda #<sio_sector_buf\n    sta DBUFLO" in sector_dcb
assert "lda #>sio_sector_buf\n    sta DBUFHI" in sector_dcb
assert copy_source.count("jsr copy_ui_prepare_data") == 3
assert copy_source.count("lda #<sio_sector_buf\n    ldy #>sio_sector_buf") == 2
write_sector_proc = sio_source.split(".proc sio_write_sector", 1)[1].split(
    ".endproc", 1
)[0]
assert "lda #CMD_PUT" in write_sector_proc
assert "CMD_WRITE" not in write_sector_proc
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
# Klasyczny READ sektora 1 poprzedza pierwszy STATUS. Standardowy XF551 jest
# obslugiwany dodatkowa prowokacja READ 4 i drugim STATUS jeszcze przed
# przyjeciem geometrii oraz PERCOM.
probe_start = main_source.index(".proc probe_drive")
probe_end = main_source.index("probe_standard:", probe_start)
probe_prefix = main_source[probe_start:probe_end]
assert probe_prefix.index("jsr sio_read_boot_sector") < probe_prefix.index("jsr sio_status")
assert probe_prefix.index("jsr sio_status") < probe_prefix.index(
    "jsr probe_standard_xf_density"
)
# STATUS rozstrzyga klase aktualnego nosnika. Stary albo ustawiony poleceniem
# WRITE PERCOM profil nie moze nadpisac DD jako ED ani odwrotnie.
fallback_proc = geometry_source.split(".proc geo_set_fallback", 1)[1].split(
    ".endproc", 1
)[0]
assert fallback_proc.index("and #$20") < fallback_proc.index("bmi enhanced")
percom_proc = geometry_source.split(".proc geo_set_percom", 1)[1].split(
    ".endproc", 1
)[0]
assert "and #$20" in percom_proc
assert "bmi status_ed" in percom_proc
assert "lda sio_percom_buf+6" in percom_proc
assert "cmp #26" in percom_proc
assert percom_proc.index("and #$20") < percom_proc.index("density_agrees:")
assert percom_proc.index("and #$20") < percom_proc.index("bmi status_ed")

# Stockowy XF551 rozpoznaje fizyczny DD dopiero na sektorze >=4. Sonda jest
# ograniczona do rozpoznanej rodziny XF, ale celowo nie ufa pierwszym bitom
# gestosci. Wykonuje jedna probe 256 B, a po dziewieciu ramkach pobiera STATUS.
xf_density = main_source.split(".proc probe_standard_xf_density", 1)[1].split(
    ".endproc", 1
)[0]
assert "and #$A0" not in xf_density
assert "cmp #$FE" in xf_density
assert "cmp #$40" in xf_density
assert "jsr sio_probe_xf_dd" in xf_density
assert "lda #9\n    jsr wait_scan_frames" in xf_density
assert xf_density.index("jsr sio_probe_xf_dd") < xf_density.index("jsr sio_status")
assert "sta probe_status3" in xf_density
assert "lda probe_status3\n    sta sio_status_buf+2" in xf_density
xf_sio_probe = sio_source.split(".proc sio_probe_xf_dd", 1)[1].split(
    ".endproc", 1
)[0]
assert "lda #4\n    sta DAUX1" in xf_sio_probe
assert "lda #0\n    sta DBYTLO\n    lda #1\n    sta DBYTHI" in xf_sio_probe
assert "lda #1\n    ldx #1\n    jsr hsio_probe_once" in xf_sio_probe
assert "hsio_probe_once  = $3A3F" in blob_source

# Standardowy XF551 nie potrafi rozroznic logicznego formatu 180/360 KB.
# Nie wolno uznawac odczytu pojedynczego sektora drugiej strony za dowod jej
# przynaleznosci do biezacego formatu. Kopier oznacza ten przypadek wartoscia
# 2, domyslnie wybiera 1S i pozwala swiadomie przelaczyc bit wyboru klawiszem G.
assert ".proc probe_standard_xf_dd_sides" not in main_source
assert "lda #$A0\n    sta sio_sector_lo" not in main_source
xf_side_gate = main_source.split("possible_standard_xf:", 1)[1].split(
    "standard_done:", 1
)[0]
assert "and #$20" in xf_side_gate
assert "bmi" not in xf_side_gate
assert "lda #2\n    sta geo_percom_ok,x" in xf_side_gate
assert "jsr set_xf_sides" in xf_side_gate
xf_side_choice = main_source.split(".proc set_xf_sides", 1)[1].split(
    ".endproc", 1
)[0]
assert "lda #1" in xf_side_choice
assert "lda format_enabled\n    asl a" in xf_side_choice
assert "adc #0" in xf_side_choice
assert "sta geo_sides,x" in xf_side_choice
geometry_toggle = main_source.split("toggle_geometry:", 1)[1].split(
    "show_memory:", 1
)[0]
assert "cmp #2" in geometry_toggle
assert "eor #$80" in geometry_toggle
assert "jsr set_xf_sides" in geometry_toggle
assert "'G'|$80, \"EOMETRIA" in main_source
next_source_block = main_source.split("next_source:", 1)[1].split(
    "next_target:", 1
)[0]
rescan_block = main_source.split("rescan:", 1)[1].split(
    "toggle_geometry:", 1
)[0]
for reset_block in (next_source_block, rescan_block):
    assert "asl format_enabled\n    lsr format_enabled" in reset_block
assert "jsr probe_drive" in next_source_block


def xf_standard_sides(format_flags: int) -> int:
    """Model 6502 ASL + LDA #1 + ADC #0 used by set_xf_sides."""
    return 1 + ((format_flags >> 7) & 1)


assert xf_standard_sides(0x00) == 1
assert xf_standard_sides(0x01) == 1  # formatowanie nie zmienia geometrii
assert xf_standard_sides(0x80) == 2
assert xf_standard_sides(0x81) == 2
assert ".proc hyperxf_track_valid" in main_source
assert ".proc probe_hyperxf_track" in main_source
assert "cmp #$C0\n    beq advance_entry" in main_source
assert "hyperxf_ambiguous:" in main_source
hyperxf_ambiguous = main_source.split("hyperxf_ambiguous:", 1)[1].split(
    "hyperxf_shape_ready:", 1
)[0]
assert "lda #1\n    sta geo_present,x" in hyperxf_ambiguous
assert "lda #2\n    sta geo_percom_ok,x" in hyperxf_ambiguous
assert "jsr set_xf_sides" in hyperxf_ambiguous
assert "jmp hyperxf_probe_done" in hyperxf_ambiguous
for track in (0, 39, 40, 79, 80, 159):
    assert f"ldx #{track}" in main_source
assert "lda #80\n    sta geo_tracks,x" in main_source
assert "sta copy_reading+17" in main_source
assert "sta copy_writing+17" in main_source
assert "PROGRESS_SPEED_COL  = 31" in main_source
assert "ldx #27\n    jsr ui_set_cursor" in main_source
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
# DOHIDET=$3A3F, czyli przesuniecie $BA od poczatku obrazu $3985. Pierwsze
# instrukcje musza zapisac A jako liczbe prob calego rozkazu i X jako liczbe
# prob ramki; bez tej kontroli zmiana zewnetrznego bloba uniewaznilaby sonde.
assert hsio_image[6 + 0xBA : 6 + 0xBE] == bytes((0x85, 0x39, 0x86, 0x38))

print(
    f"OK: {len(CASES)} geometry/buffer cases, HyperXF track-table validation, "
    "sector-length source, "
    "multi-pass chunking, scratch-backed SIO with in-pass visualization, centered "
    "32-column sector windows, four stage palettes, clean media prompts, buffered-write retry, "
    "repeat copy from one-pass buffer, START/SELECT confirmation, instant K: "
    "input, joined semigraphic menu C3, HyperXF identity/skew diagnostics, "
    "row-mirrored buffer loops, own HSIO without SIOV, XF551 READ4 density "
    "probe, verified HSIO blob, "
    "eight-drive limit, track/disk progress bars, and 38-column UI literals"
)
