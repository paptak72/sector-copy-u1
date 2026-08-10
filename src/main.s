.include "os.inc"

; ---------------------------------------------------------------------------
; Program glowny, interfejs i maszyna stanow kopiowania
; ---------------------------------------------------------------------------
;
; Punkt RUNAD prowadzi do start. Najpierw zapisywane jest srodowisko programu
; wywolujacego, potem uzytkownik wybiera pelne przejecie komputera albo tryb
; zachowania DOS-u. Od initialize kod nie zalezy juz od tego, czy XEX wczytal
; SpartaDOS X, inny DOS, czy prosty program ladujacy.
;
; Glowne stany operacji K:
;
;   menu -> przygotowanie geometrii -> potwierdzenie -> ODCZYT do bankow
;        -> zmiana/format celu -> ZAPIS -> opcjonalna WERYFIKACJA
;        -> kolejna porcja albo ekran sukcesu
;
; Po poprawnym odczycie porcji dane pozostaja w bankach az do jawnego powrotu
; do odczytu. Bledy celu prowadza do target_retry_error, skad R ponawia zapis,
; a F ponawia format i zapis bez dotykania dyskietki zrodlowej. Ma to znaczenie
; przy jednej stacji i wieloprzebiegowej kopii: udany odczyt starego nosnika
; nie jest tracony z powodu ochrony zapisu albo wadliwej dyskietki docelowej.
;
; Ten modul zawiera rowniez ekran glowny i wizualizacje sektora, bo ich stan
; jest scisle zwiazany z przebiegiem kopiowania. Niskopoziomowe CIO/kolory sa
; w ui.s, operacje SIO w sio.s, geometria w geometry.s, a petle danych w copy.s.

.import ui_begin_screen
.import ui_init
.import ui_get_key_upper
.import ui_wait_start_select
.import ui_wait_key
.import ui_delay_notice
.import ui_colors_read
.import ui_colors_write
.import ui_colors_verify
.import ui_set_cursor
.import ui_print_char
.import ui_print_eol
.import ui_print_z
.import ui_print_u8
.import ui_print_u16

.import sio_status
.import sio_status_force
.import sio_hyperxf_track_info
.import sio_get_percom
.import sio_clear_speeds
.import sio_get_mode
.import sio_read_boot_sector
.import sio_read_sector
.import sio_result
.import sio_status_buf
.import sio_percom_buf
.import sio_sector_buf
.import sio_sector_lo
.import sio_sector_hi
.import sio_length_lo
.import sio_length_hi
.import sio_actual_mode

.import geo_clear
.import geo_set_fallback
.import geo_set_percom
.import geo_set_speed
.import geo_calculate_total
.import geo_present
.import geo_tracks
.import geo_sides
.import geo_spt_lo
.import geo_spt_hi
.import geo_bps_lo
.import geo_bps_hi
.import geo_total_lo
.import geo_total_hi
.import geo_speed_kind
.import geo_speed_div
.import geo_percom_ok

.import memory_probe
.import memory_takeover
.import memory_keep_dos
.import memory_detect_launch
.import memory_save_environment
.import memory_reserve_application
.import memory_restore_environment
.import memory_build_bank_list
.import mem_sdx
.import mem_dos_present
.import mem_keep_dos
.import mem_free_banks
.import mem_total_banks
.import mem_usable_banks
.import mem_pbmask
.import mem_main_free_lo
.import mem_main_free_hi
.import mem_buffer_units_lo
.import mem_buffer_units_hi

.import copy_prepare
.import copy_validate_target
.import copy_validate_source
.import copy_begin_chunks
.import copy_advance_chunk
.import copy_read_all
.import copy_write_all
.import copy_verify_all
.import copy_format_target
.import copy_source
.import copy_target
.import copy_required_banks
.import copy_single_pass
.import copy_error_kind
.import copy_error_sector_lo
.import copy_error_sector_hi
.import copy_error_status
.import copy_current_lo
.import copy_current_hi
.import copy_total_lo
.import copy_total_hi
.import copy_chunk_start_lo
.import copy_chunk_start_hi
.import copy_chunk_end_lo
.import copy_chunk_end_hi
.import copy_pass_number

.export copy_ui_progress

; Interfejs i tablice geometrii obsluguja D1:..D8:. Skanujemy caly ten zakres,
; a klawisze Z/C przechodza pozniej tylko po wpisach geo_present<>0.
SCAN_DRIVES = 8

PROGRESS_NUMBER_ROW = 3
PROGRESS_NUMBER_COL = 18
PROGRESS_SPEED_COL  = 35
PROGRESS_DATA_COL   = 4
PROGRESS_BAR_ROW    = 21
PROGRESS_BAR_COL    = 1
TRACK_BAR_OFFSET    = 3
DISK_LABEL_OFFSET   = 40
DISK_BAR_OFFSET     = 43
SCREEN_HLINE        = $52
; Kod $54 tworzy waski, zaokraglony segment semigraficzny. Oddzielne komorki
; zachowuja czytelna podzialke obu paskow postepu.
SCREEN_PROGRESS     = $54
SCREEN_BOX_TL       = $51
SCREEN_BOX_TR       = $45
SCREEN_BOX_BL       = $5A
SCREEN_BOX_BR       = $43
; Stockowy glif $7C ma pion $18 posrodku wszystkich osmiu skanlinii. Dziala
; poprawnie juz na ekranie wyboru trybu, zanim program przejmie komputer.
SCREEN_BOX_V        = $7C

.segment "ZEROPAGE"
progress_src_ptr: .res 2
progress_dst_ptr: .res 2
hyperxf_sector_count: .res 1
; Trzy ostatnie bajty z zachowywanego zakresu $80-$8F sluza licznikom paskow.
progress_disk_step: .res 1
progress_disk_cell: .res 1
progress_divisor:  .res 1

.segment "BSS"
source_drive:     .res 1
target_drive:     .res 1
scan_index:       .res 1
verify_enabled:   .res 1
format_enabled:   .res 1
target_initialized: .res 1
progress_render_rows:.res 1
cycle_start:      .res 1
probe_status0:    .res 1
probe_status3:    .res 1
progress_track_pos:.res 1
progress_track_spt:.res 1

; Te dwa bajty maja rozlaczne fazy zycia. cycle_start/probe_status3 sluza
; tylko menu i wykrywaniu stacji, a po rozpoczeciu kopiowania przechowuja
; stan skalera pierwszego paska bez powiekszania ciasnego segmentu BSS.
progress_track_cell = cycle_start
progress_track_accum = probe_status3

.segment "RODATA"
; Maska numeru sektora modulo 8 dla walidatora odpowiedzi HyperXF $67.
hyperxf_bit_mask:
    .byte $01, $02, $04, $08, $10, $20, $40, $80
.segment "AUXCODE"
title:
    .byte "SECTOR COPY U1 0.6.7", ATASCII_EOL
    .byte "             Paptak 2026", 0
.segment "RODATA"
launch_title:
    .byte "TRYB URUCHOMIENIA:", ATASCII_EOL, 0
launch_full:
    .byte "1 PELNY - BEZ DOS", ATASCII_EOL, 0
launch_keep:
    .byte "2 ZACHOWAJ DOS", ATASCII_EOL, 0
launch_exit:
    .byte "Q/ESC POWROT", ATASCII_EOL, 0
keep_unavailable:
    .byte "DOS ZAJMUJE BUFOR", ATASCII_EOL
    .byte "KLAWISZ - POWROT", 0
source_panel_title:
    .byte 'Z'|$80, "RODLO", 0
target_panel_title:
    .byte 'C'|$80, "EL", 0
kb_label:
    .byte " KB", 0
sectors_short_label:
    .byte " S", 0

; Stale teksty paneli zajmuja zachowywany obszar $3600-$37FF. Pozwala to
; rozbudowac opis formatu bez wejscia programu w obszar BASIC/kartridza od
; $A000.
.segment "AUXCODE"
offline_label:
    .byte "BRAK STACJI", 0
single_density_label:
    .byte "POJEDYNCZA (SD)", 0
enhanced_density_label:
    .byte "ROZSZERZ. (ED)", 0
double_density_label:
    .byte "PODWOJNA (DD)", 0
double_sided_label:
    .byte "PODW. 2-STRONNA", 0
sector_512_label:
    .byte "SEKTORY 512 B", 0
std_label:
    .byte "SIO STANDARD", 0
us_label:
    .byte " US", 0
hxf_label:
    .byte " HXF", 0
xf_label:
    .byte " XFHS", 0
turbo_label:
    .byte " 1050/", 0
warp_label:
    .byte " WARP", 0
turbo_prefix:
    .byte "TURBO", 0
.segment "RODATA"
copy_action:
    .byte 'K'|$80, "OPIUJ DYSKIETKE", 0
settings_title:
    .byte "---USTAWIENIA---", 0
bottom_menu:
    .byte 'S'|$80, "KAN   ", 'P'|$80, "AMIEC   ", 'Q'|$80, "UIT", 0
scan_message:
    .byte "SKAN D1-D8...", 0
memory_title:
    .byte "PAMIEC", ATASCII_EOL, 0
sdx_yes:
    .byte "SPARTADOS X", ATASCII_EOL, 0
dos_yes:
    .byte "DOS / LOADER", ATASCII_EOL, 0
sdx_no:
    .byte "SAMODZIELNY XEX", ATASCII_EOL, 0
mode_full:
    .byte "TRYB: PELNY", ATASCII_EOL, 0
mode_keep:
    .byte "TRYB: DOS ZACHOWANY", ATASCII_EOL, 0
main_mode_full:
    .byte "TRYB: PELNY  ", 0
main_mode_keep:
    .byte "TRYB: DOS  ", 0
free_banks_label:
    .byte "BANKI EXT 16K: ", 0
total_banks_label:
    .byte "BANKI RAZEM: ", 0
pbmask_label:
    .byte "MASKA PORTB: $", 0
one_pass_yes:
    .byte "720K: "
copy_one_pass:
    .byte "JEDEN PRZEBIEG", ATASCII_EOL, 0
one_pass_no:
    .byte "720K: "
copy_multi_pass:
    .byte "WIELE PRZEBIEGOW", ATASCII_EOL, 0
return_label:
    .byte ATASCII_EOL, "KLAWISZ - POWROT", 0
copy_title:
    .byte "PARAMETRY KOPII", 0
copy_from_label:
    .byte "ZRODLO D", 0
copy_to_label:
    .byte "CEL    D", 0
usable_banks_label:
    .byte "BUFOR 16K: ", 0
verify_label:
    .byte 'W'|$80, "ERYFIKACJA: ", 0
format_label:
    .byte 'F'|$80, "ORMAT: ", 0
format_same_label:
    .byte "JAK ZRODLO", 0
format_no_label:
no_label:
    .byte "NIE", 0
yes_label:
    .byte "TAK", 0
buffer_short_label:
    .byte "BUF: ", 0
copy_warning_overwrite:
    .byte "UWAGA: CEL ZOSTANIE NADPISANY", 0
copy_warning_deleted:
    .byte "DANE ZOSTANA USUNIETE", 0
.segment "RODATA"
confirm_media_title:
    .byte "---NOSNIKI---", 0
confirm_data_title:
    .byte "---DANE I PAMIEC---", 0
confirm_geometry_label:
    .byte "GEOMETRIA   ", 0
confirm_sectors_label:
    .byte "SEKTORY     ", 0
confirm_buffer_label:
    .byte "BUFOR 16 KB ", 0
confirm_passes_label:
    .byte "PRZEBIEGI   ", 0
confirm_geometry_sep:
    .byte " / ", 0
confirm_bytes_suffix:
    .byte " B", 0
confirm_one_pass:
    .byte "1", 0
confirm_many_passes:
    .byte "2+", 0
.segment "AUXCODE"
continue_prompt:
    ; $09 tworzy lewy skos klawisza, a jego wersja w negatywie $89 prawy.
    .byte ATASCII_EOL, ATASCII_ESC, $09
    .byte 'S'|$80, 'T'|$80, 'A'|$80, 'R'|$80, 'T'|$80
    .byte ATASCII_ESC, $89, " - DALEJ  "
    .byte ATASCII_ESC, $09
    .byte 'S'|$80, 'E'|$80, 'L'|$80, 'E'|$80, 'C'|$80, 'T'|$80
    .byte ATASCII_ESC, $89, " - ANULUJ", 0
.segment "RODATA"
copy_reading:
    .byte "          ETAP 1/3 - ODCZYT", ATASCII_EOL, 0
.segment "AUXCODE"
copy_chunk_label:
    .byte "PRZEBIEG ", 0
.segment "RODATA"
copy_range_label:
    .byte "  SEKTORY ", 0
copy_insert_target:
    .byte "ODCZYT GOTOWY.", ATASCII_EOL
    .byte "WLOZ DYSK DOCELOWY DO D", 0
media_prompt_title:
    .byte "PRZYGOTUJ DYSKIETKE", ATASCII_EOL, 0
.segment "AUXCODE"
copy_last_warning:
    .byte "POTWIERDZ ZAPIS NA DYSKU DOCELOWYM.", ATASCII_EOL, 0
.segment "RODATA"
copy_insert_source_next:
    .byte "WLOZ DYSK ZRODLOWY DO D", 0
copy_formatting:
    .byte "FORMATOWANIE CELU...", ATASCII_EOL, 0
hyperxf_format_ultra:
    .byte "HYPERXF SKEW: ULTRASPEED", ATASCII_EOL, 0
hyperxf_format_standard:
    .byte "HYPERXF SKEW: STANDARD", ATASCII_EOL, 0
copy_writing:
    .byte "          ETAP 2/3 - ZAPIS", ATASCII_EOL, 0
copy_verifying:
    .byte "        ETAP 3/3 - WERYFIKACJA", ATASCII_EOL, 0
progress_sector_label:
    .byte "SEKTOR $", 0
progress_total_sep:
    .byte " / $", 0
progress_sio_label:
    .byte "SIO ", 0
progress_rows:
    .byte 4, 8, 16
progress_offset_lo:
    .byte <(10*40+PROGRESS_DATA_COL)
    .byte <(8*40+PROGRESS_DATA_COL)
    .byte <(4*40+PROGRESS_DATA_COL)
progress_offset_hi:
    .byte >(10*40+PROGRESS_DATA_COL)
    .byte >(8*40+PROGRESS_DATA_COL)
    .byte >(4*40+PROGRESS_DATA_COL)

; Pelna tablica ATASCII -> kod ekranowy GR.0. Odczyt indeksowany obsluguje
; jednakowo znaki kontrolne, semigrafike oraz negatyw i ma staly czas dla
; kazdego bajtu. Ogranicza to koszt wizualizacji, aby obsluga ekranu miescila
; sie w czasie miedzy sektorami wynikajacym z przeplotu HyperXF UltraSpeed.
atascii_screen_table:
    .byte $40,$41,$42,$43,$44,$45,$46,$47,$48,$49,$4A,$4B,$4C,$4D,$4E,$4F
    .byte $50,$51,$52,$53,$54,$55,$56,$57,$58,$59,$5A,$5B,$5C,$5D,$5E,$5F
    .byte $00,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F
    .byte $10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$1A,$1B,$1C,$1D,$1E,$1F
    .byte $20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$2A,$2B,$2C,$2D,$2E,$2F
    .byte $30,$31,$32,$33,$34,$35,$36,$37,$38,$39,$3A,$3B,$3C,$3D,$3E,$3F
    .byte $60,$61,$62,$63,$64,$65,$66,$67,$68,$69,$6A,$6B,$6C,$6D,$6E,$6F
    .byte $70,$71,$72,$73,$74,$75,$76,$77,$78,$79,$7A,$7B,$7C,$7D,$7E,$7F
    .byte $C0,$C1,$C2,$C3,$C4,$C5,$C6,$C7,$C8,$C9,$CA,$CB,$CC,$CD,$CE,$CF
    .byte $D0,$D1,$D2,$D3,$D4,$D5,$D6,$D7,$D8,$D9,$DA,$DB,$DC,$DD,$DE,$DF
    .byte $80,$81,$82,$83,$84,$85,$86,$87,$88,$89,$8A,$8B,$8C,$8D,$8E,$8F
    .byte $90,$91,$92,$93,$94,$95,$96,$97,$98,$99,$9A,$9B,$9C,$9D,$9E,$9F
    .byte $A0,$A1,$A2,$A3,$A4,$A5,$A6,$A7,$A8,$A9,$AA,$AB,$AC,$AD,$AE,$AF
    .byte $B0,$B1,$B2,$B3,$B4,$B5,$B6,$B7,$B8,$B9,$BA,$BB,$BC,$BD,$BE,$BF
    .byte $E0,$E1,$E2,$E3,$E4,$E5,$E6,$E7,$E8,$E9,$EA,$EB,$EC,$ED,$EE,$EF
    .byte $F0,$F1,$F2,$F3,$F4,$F5,$F6,$F7,$F8,$F9,$FA,$FB,$FC,$FD,$FE,$FF
copy_success:
    .byte ATASCII_EOL, "KOPIA I WERYFIKACJA OK.", ATASCII_EOL, 0
copy_success_no_verify:
    .byte ATASCII_EOL, "KOPIA OK (BEZ WERYFIKACJI)", ATASCII_EOL, 0
next_copy_insert:
    .byte ATASCII_EOL, "WLOZ NASTEPNA DYSKIETKE DO D", 0
.segment "AUXCODE"
next_copy_choices:
    .byte ATASCII_ESC, $09
    .byte 'S'|$80, 'T'|$80, 'A'|$80, 'R'|$80, 'T'|$80
    .byte ATASCII_ESC, $89, " - ZAPISZ Z BUFORA", ATASCII_EOL
    .byte ATASCII_ESC, $09
    .byte 'S'|$80, 'E'|$80, 'L'|$80, 'E'|$80, 'C'|$80, 'T'|$80
    .byte ATASCII_ESC, $89, " - POWROT DO MENU", 0
.segment "RODATA"
copy_error_title:
    .byte "KOPIA PRZERWANA", ATASCII_EOL, 0
copy_error_label:
    .byte "KOD PROGRAMU: ", 0
copy_error_sector_label:
    .byte "  SEKTOR: ", 0
copy_error_sio_label:
    .byte "  SIO: ", 0
copy_error_help:
    .byte ATASCII_EOL
    .byte "1 ZRODLO  2 CEL  3 GEOMETRIA", ATASCII_EOL
    .byte "4 PAMIEC  5 ODCZYT  6 ZAPIS", ATASCII_EOL
    .byte "7 WER.SIO  8 DANE  9 BUF  10 FORMAT", ATASCII_EOL, 0
.segment "CODE"

.proc start
    jsr memory_save_environment
    jsr memory_detect_launch
    jsr memory_reserve_application
    jsr ui_init
    lda mem_dos_present
    beq select_full
    jsr choose_launch_mode
    cmp #2
    beq select_keep
    cmp #1
    beq select_full
    jsr memory_restore_environment
    rts

select_full:
    ; Tryb pelny swiadomie porzuca stos powrotu do programu ladujacego.
    sei
    ldx #$FF
    txs
    cli
    jsr memory_takeover
    jmp initialize

select_keep:
    jsr memory_keep_dos
    bcc initialize
    jsr ui_begin_screen
    lda #<keep_unavailable
    ldy #>keep_unavailable
    jsr ui_print_z
    jsr ui_wait_key
    jsr memory_restore_environment
    rts

initialize:
    lda #1
    sta source_drive
    lda #2
    sta target_drive
    lda #1
    sta verify_enabled
    sta format_enabled
    jsr geo_clear
    jsr scan_all

main_loop:
    jsr draw_main
    jsr ui_get_key_upper
    cmp #'Z'
    beq next_source
    cmp #'C'
    beq next_target
    cmp #'S'
    beq rescan
    cmp #'P'
    beq show_memory
    cmp #'K'
    beq start_copy
    cmp #'F'
    beq toggle_format
    cmp #'W'
    beq toggle_verify
    cmp #'Q'
    beq quit
    cmp #ATASCII_ESC
    beq quit
    jmp main_loop

next_source:
    lda source_drive
    jsr next_detected_drive
    sta source_drive
    jmp main_loop

next_target:
    lda target_drive
    jsr next_detected_drive
    sta target_drive
    jmp main_loop

rescan:
    jsr scan_all
    jmp main_loop

show_memory:
    jsr draw_memory
    jsr ui_wait_key
    jmp main_loop

start_copy:
    jsr do_copy
    jmp main_loop

toggle_verify:
    lda verify_enabled
    eor #1
    sta verify_enabled
    jmp main_loop

toggle_format:
    lda format_enabled
    eor #1
    sta format_enabled
    jmp main_loop

quit:
    lda mem_keep_dos
    beq cold_restart
    jsr memory_restore_environment
    rts
cold_restart:
    jmp COLDSV
.endproc

; Wyjscie: A=1 tryb pelny, A=2 zachowanie DOS-u, A=0 powrot do wywolujacego.
.proc choose_launch_mode
redraw:
    jsr ui_begin_screen
    lda #<title
    ldy #>title
    jsr ui_print_z
    jsr print_separator
    lda #<launch_title
    ldy #>launch_title
    jsr ui_print_z
    lda #<launch_full
    ldy #>launch_full
    jsr ui_print_z
    lda #<launch_keep
    ldy #>launch_keep
    jsr ui_print_z
    lda #<launch_exit
    ldy #>launch_exit
    jsr ui_print_z
wait:
    jsr ui_get_key_upper
    cmp #'1'
    beq full
    cmp #'2'
    beq keep
    cmp #'Q'
    beq exit
    cmp #ATASCII_ESC
    beq exit
    jmp wait
full:
    lda #1
    rts
keep:
    lda #2
    rts
exit:
    lda #0
    rts
.endproc

.proc scan_all
    jsr ui_begin_screen
    lda #<scan_message
    ldy #>scan_message
    jsr ui_print_z
    jsr ui_print_eol
    jsr sio_clear_speeds
    jsr geo_clear
    lda #1
    sta scan_index

next_drive:
    lda #'D'
    jsr ui_print_char
    lda scan_index
    jsr ui_print_u8
    lda #' '
    jsr ui_print_char

    lda scan_index
    jsr probe_drive
    bcs no_drive
    lda #'O'
    jsr ui_print_char
    lda #'K'
    jsr ui_print_char
    jmp scanned

no_drive:
    lda #'-'
    jsr ui_print_char

scanned:
    jsr ui_print_eol
    inc scan_index
    lda scan_index
    cmp #SCAN_DRIVES+1
    bcc next_drive

    ; Ponowny skan moze odbyc sie po odlaczeniu lub zmianie numeru stacji.
    ; Nie pozostawiamy wtedy wskazania na nieistniejace Dn:. Jezeli nie ma
    ; zadnej odpowiedzi, ensure_detected_drive zachowuje dotychczasowy numer
    ; jako nieaktywny symbol z napisem BRAK STACJI.
    lda source_drive
    jsr ensure_detected_drive
    sta source_drive
    lda target_drive
    jsr ensure_detected_drive
    sta target_drive
    rts
.endproc

; A = aktualnie wybrana stacja. Zwraca nastepna wykryta stacje, z zawijaniem
; D8: -> D1:. Gdy skan nie wykryl zadnej, zwraca niezmienione A. Dzieki temu
; pojedyncza stacja jest jednoczesnie zrodlem i celem (kopiowanie z wymiana
; dyskietki), a klawisze Z/C nigdy nie zatrzymuja sie na pustym numerze.
.proc next_detected_drive
    sta cycle_start
next:
    clc
    adc #1
    cmp #SCAN_DRIVES+1
    bcc test
    lda #1
test:
    tax
    dex
    ldy geo_present,x
    bne found
    cmp cycle_start
    bne next
found:
    rts
.endproc

; Zachowaj A, jesli wskazuje obecna stacje; w przeciwnym razie znajdz pierwsza
; dostepna po niej. next_detected_drive wykona pelny obieg, wiec osobna tablica
; listy urzadzen nie jest potrzebna.
.proc ensure_detected_drive
    tax
    dex
    ldy geo_present,x
    bne present
    jmp next_detected_drive
present:
    rts
.endproc

; Sprawdz, czy blok zwrocony przez HyperXF GET TRACK INFO rzeczywiscie opisuje
; cala, poprawna sciezke w aktualnie wykrytej gestosci. Sam kod powodzenia SIO
; nie wystarcza: komenda $67 zwraca tablice sektorow, w ktorej moga znajdowac
; sie stare naglowki, duplikaty albo kody bledow nosnika.
;
; Format bloku jest taki sam jak dla komendy rozszerzonego formatowania $65:
; bajty 12..56 sa zakonczona zerem tablica sektorow. Niskie piec bitow to
; numer 1..18 (SD/DD) albo 1..26 (MD), a bity 7..5 opisuja stan. Dopuszczamy
; tylko $00 (poprawny/pusty) i $E0 (poprawny/niepusty). W odpowiedzi moga
; wystapic wpisy $C0 opisujace fizyczne odstepy miedzy sektorami. Nie sa one
; sektorami ani bledami i sa pomijane. Cztery pierwsze bajty bufora, ktore nie
; sa juz potrzebne po odpowiedzi $67, sluza jako 32-bitowa mapa wykrytych
; numerow. Wymaganie dokladnie jednego kompletu eliminuje duplikaty oraz
; przypadkowe uznanie pojedynczego starego naglowka za cala strone dyskietki.
;
; Wyjscie: C=0 kompletna sciezka, C=1 odpowiedz niepelna lub uszkodzona.
.proc hyperxf_track_valid
    ldx scan_index
    dex
    lda geo_spt_lo,x
    sta probe_status0

    lda #0
    ldx #3
clear_seen:
    sta sio_sector_buf,x
    dex
    bpl clear_seen
    sta hyperxf_sector_count

    ldy #12
next_header:
    lda sio_sector_buf,y
    beq end_table
    cmp #$C0
    beq advance_entry
    and #$E0
    beq status_ok
    cmp #$E0
    bne invalid
status_ok:
    lda sio_sector_buf,y
    and #$1F
    beq invalid
    cmp probe_status0
    bcc number_ok
    bne invalid
number_ok:
    sec
    sbc #1
    pha
    and #7
    tax
    lda hyperxf_bit_mask,x
    sta probe_status3
    pla
    lsr a
    lsr a
    lsr a
    tax
    lda sio_sector_buf,x
    and probe_status3
    bne invalid
    lda sio_sector_buf,x
    ora probe_status3
    sta sio_sector_buf,x
    inc hyperxf_sector_count
advance_entry:
    iny
    cpy #57
    bcc next_header
    bcs invalid
end_table:
    lda hyperxf_sector_count
    cmp probe_status0
    bne invalid
    clc
    rts
invalid:
    sec
    rts
.endproc

; X = logiczny numer sciezki. Oprocz statusu transmisji sprawdzamy zawartosc
; odpowiedzi, aby kolejny etap mogl traktowac sukces jako dowod fizycznego
; istnienia calej sciezki, a nie tylko odebrania 128 bajtow z napedu.
.proc probe_hyperxf_track
    lda scan_index
    jsr sio_hyperxf_track_info
    bcc received
    rts
received:
    jmp hyperxf_track_valid
.endproc

; Wejscie: A = numer stacji. Bada urzadzenie i aktualizuje jego geometrie.
; Wyjscie: C=0 sukces, C=1 brak odpowiedzi na STATUS.
.proc probe_drive
    sta scan_index

    ; Klasyczna sekwencja Atari: najpierw READ sektora 1. Ten dostep powoduje,
    ; ze elektronika stacji rozpoznaje kodowanie aktualnego nosnika; dopiero
    ; nastepny STATUS zwraca wiarygodne bity SD/MD/DD. Blad odczytu nie oznacza
    ; jeszcze braku stacji (dysk moze byc pusty albo uszkodzony), dlatego o
    ; obecnosci urzadzenia nadal rozstrzyga odpowiedz STATUS.
    jsr sio_read_boot_sector
    lda scan_index
    jsr sio_status
    bcc status_ok
    jmp failed
status_ok:

    ; Standardowy GET PERCOM zwykle opisuje aktualny nosnik. W HyperXF komenda
    ; N/$4E zwraca jednak ostatni blok ustawiony komenda O, a nie fizyczny
    ; rozmiar wlozonej dyskietki. Sygnatura $D9 kieruje wiec program do
    ; aktywnego badania gestosci i skrajnych sciezek zamiast uzycia PERCOM.
    lda sio_status_buf+2
    cmp #$D9
    bne probe_standard
    jmp probe_hyperxf

probe_standard:
    ldx scan_index
    dex
    jsr geo_set_fallback

    lda scan_index
    jsr sio_get_mode
    bcs no_speed
    ldx scan_index
    dex
    jsr geo_set_speed
no_speed:
    lda scan_index
    jsr sio_get_percom
    bcs no_percom
    ldx scan_index
    dex
    jsr geo_set_percom
no_percom:
    clc
    rts

probe_hyperxf:
    ; HyperXF bez czujnika klapki moze pamietac gestosc poprzedniego nosnika.
    ; STATUS z AUX2='U' wymusza fizyczne sprawdzenie gestosci przed badaniem
    ; skrajnej sciezki. Gdy sprawdzenie sie nie powiedzie (np. brak dysku),
    ; pozostawiamy odpowiedz pierwszego STATUS jako bezpieczny profil awaryjny.
    lda sio_status_buf
    sta probe_status0
    lda sio_status_buf+3
    sta probe_status3
    lda scan_index
    jsr sio_status_force
    bcc hyperxf_status_ok
    lda probe_status0
    sta sio_status_buf
    lda probe_status3
    sta sio_status_buf+3
    lda #0
    beq hyperxf_save_check
hyperxf_status_ok:
    lda #1
hyperxf_save_check:
    sta probe_status0
hyperxf_status_ready:
    ldx scan_index
    dex
    jsr geo_set_fallback

    lda scan_index
    jsr sio_get_mode
    bcs hyperxf_name
    ldx scan_index
    dex
    jsr geo_set_speed
hyperxf_name:
    ; Sygnatura $D9 jest jednoznaczna nawet wtedy, gdy szybki profil nie zostal
    ; wynegocjowany. HXF40 w menu oznaczy wtedy HyperXF pracujaca standardowo.
    ldx scan_index
    dex
    lda #5
    sta geo_speed_kind,x

    ; Profil awaryjny ustawil juz 40T/1S. HyperXF zna geometrie ustawiona przez O,
    ; dlatego oznaczenie P nie pochodzi tutaj z GET PERCOM, lecz z ponizszego
    ; aktywnego badania nosnika. Nawet profil 40T/1S jest bezpieczny do SET
    ; PERCOM podczas formatowania, bo gestosc pochodzi ze swiezego STATUS U.
    lda #1
    sta geo_percom_ok,x

    ; Bez poprawnego STATUS U nie znamy gestosci aktualnego nosnika. Zostawiamy
    ; wtedy profil minimalny, zamiast skanowac sciezki w zapamietanej gestosci.
    lda probe_status0
    beq hyperxf_shape_ready

    ; Tryby A/B/C/D sa jawnym widokiem pojedynczej partycji 40T/1S. Nie wolno
    ; ich promowac do calego nosnika tylko dlatego, ze mechanizm ma 3,5 cala.
    lda sio_status_buf+3
    and #7
    cmp #4
    bcc hyperxf_shape_ready

    ; Kazdy standardowy format musi zawierac pelny pierwszy zakres 0..39.
    ; Dalsze pary poczatek/koniec potwierdzaja ciaglosc kolejnych fragmentow:
    ;   5,25": 0,39 + 40,79                 = 40T/2S,
    ;   3,5" : 0,39 + 40,79 + 80,159        = 80T/2S.
    ; Sprawdzanie obu krancow chroni przed starym naglowkiem na jednej sciezce.
    ldx #0
    jsr probe_hyperxf_track
    bcs hyperxf_ambiguous
    ldx #39
    jsr probe_hyperxf_track
    bcs hyperxf_ambiguous
    ldx #40
    jsr probe_hyperxf_track
    bcs hyperxf_shape_ready
    ldx #79
    jsr probe_hyperxf_track
    bcs hyperxf_ambiguous

    ldx scan_index
    dex
    lda #2
    sta geo_sides,x
    lda sio_status_buf+3
    and #$40
    beq hyperxf_shape_ready

    ldx #80
    jsr probe_hyperxf_track
    bcs hyperxf_ambiguous
    ldx #159
    jsr probe_hyperxf_track
    bcs hyperxf_ambiguous
    ldx scan_index
    dex
    lda #80
    sta geo_tracks,x
    bne hyperxf_shape_ready

hyperxf_ambiguous:
    ; Widoczny tylko fragment oczekiwanej geometrii oznacza nosnik
    ; niejednoznaczny/uszkodzony. Ujemne geo_present nadal pozostawia stacje
    ; na liscie, ale copy.s odrzuci ja jako zrodlo zamiast po cichu skopiowac
    ; tylko pierwsze 40 sciezek. Pusta dyskietka nadal moze byc celem FORMAT.
    ldx scan_index
    dex
    lda #$80
    sta geo_present,x
    lda #1
    sta geo_sides,x
hyperxf_shape_ready:
    ldx scan_index
    dex
    jsr geo_calculate_total

    ; W trybach M/F ta sama fizyczna HyperXF moze odpowiadac jako kilka Dn:.
    ; Jednostka partycji A udostepnia caly nosnik, lecz B-D tylko po 40T/1S.
    ; Nie wnioskujemy z kolejnych numerow Dn:, bo moga nalezec do innych
    ; urzadzen. Gdy $67 pokazal pelny zakres, zwykly READ ostatniego sektora
    ; potwierdza, ze aktualna jednostka ma ten sam widok dla normalnego R/W.
    ; X i S sa z definicji widokami calego nosnika, A-D zostaly juz ograniczone.
    lda geo_present,x
    bmi hyperxf_probe_done
    lda sio_status_buf+3
    and #7
    cmp #4
    bcc hyperxf_probe_done
    cmp #6
    bcs hyperxf_probe_done
    lda geo_sides,x
    cmp #2
    bne hyperxf_probe_done
    lda geo_total_lo,x
    sta sio_sector_lo
    lda geo_total_hi,x
    sta sio_sector_hi
    lda geo_bps_lo,x
    sta sio_length_lo
    lda geo_bps_hi,x
    sta sio_length_hi
    lda scan_index
    jsr sio_read_sector
    bcc hyperxf_probe_done

    ; Brak zwyklego dostepu do sektora koncowego oznacza widok partycji.
    ; Zostawiamy poprawny profil 40T/1S zamiast przypisac partycji B-D caly
    ; dysk. Koncowy STATUS U ponizej usuwa flage kontroli gestosci po RNF.
    ldx scan_index
    dex
    lda #40
    sta geo_tracks,x
    lda #1
    sta geo_sides,x
    jsr geo_calculate_total
hyperxf_probe_done:
    ; Nieudane badanie sciezki ustawia w HyperXF flage ponownego rozpoznania
    ; gestosci. Koncowy STATUS U porzadkuje stan napedu przed zwyklym R/W.
    lda scan_index
    jsr sio_status_force
    clc
    rts
failed:
    ldx scan_index
    dex
    lda #0
    sta geo_present,x
    sec
    rts
.endproc

.proc draw_main
    jsr ui_begin_screen
    lda #1
    ldx #9
    jsr ui_set_cursor
    lda #<title
    ldy #>title
    jsr ui_print_z

    ldx #1
    jsr draw_panel_box
    ldx #21
    jsr draw_panel_box

    lda #4
    ldx #7
    jsr ui_set_cursor
    lda #<source_panel_title
    ldy #>source_panel_title
    jsr ui_print_z
    lda #4
    ldx #28
    jsr ui_set_cursor
    lda #<target_panel_title
    ldy #>target_panel_title
    jsr ui_print_z

    lda source_drive
    ldx #3
    jsr draw_selected_panel
    lda target_drive
    ldx #23
    jsr draw_selected_panel

    lda #12
    ldx #12
    jsr ui_set_cursor
    lda #<copy_action
    ldy #>copy_action
    jsr ui_print_z

    lda #14
    ldx #12
    jsr ui_set_cursor
    lda #<settings_title
    ldy #>settings_title
    jsr ui_print_z

    lda #16
    ldx #4
    jsr ui_set_cursor
    jsr print_format_state

    lda #17
    ldx #4
    jsr ui_set_cursor
    lda #<verify_label
    ldy #>verify_label
    jsr ui_print_z
    lda verify_enabled
    beq verify_off
    lda #<yes_label
    ldy #>yes_label
    jsr ui_print_z
    jmp show_mode
verify_off:
    lda #<no_label
    ldy #>no_label
    jsr ui_print_z
show_mode:
    lda #18
    ldx #4
    jsr ui_set_cursor
    lda mem_keep_dos
    beq main_full_mode
    lda #<main_mode_keep
    ldy #>main_mode_keep
    jsr ui_print_z
    jmp main_mode_done
main_full_mode:
    lda #<main_mode_full
    ldy #>main_mode_full
    jsr ui_print_z
main_mode_done:
    lda #<buffer_short_label
    ldy #>buffer_short_label
    jsr ui_print_z
    lda mem_usable_banks
    jsr ui_print_u8

    lda #21
    ldx #10
    jsr ui_set_cursor
    lda #<bottom_menu
    ldy #>bottom_menu
    jsr ui_print_z
    rts
.endproc

; Rysuje wewnetrzny panel 18x8 od wiersza 3. Wejscie: X = lewa kolumna.
.proc draw_panel_box
    stx scan_index
    lda SAVMSC
    clc
    adc #<(3*40)
    sta progress_dst_ptr
    lda SAVMSC+1
    adc #>(3*40)
    sta progress_dst_ptr+1
    txa
    clc
    adc progress_dst_ptr
    sta progress_dst_ptr
    bcc :+
    inc progress_dst_ptr+1
:
    ldy #0
    lda #SCREEN_BOX_TL
    sta (progress_dst_ptr),y
    iny
    lda #SCREEN_HLINE
top:
    sta (progress_dst_ptr),y
    iny
    cpy #17
    bcc top
    lda #SCREEN_BOX_TR
    sta (progress_dst_ptr),y

    ldx #6
sides:
    lda progress_dst_ptr
    clc
    adc #40
    sta progress_dst_ptr
    bcc :+
    inc progress_dst_ptr+1
:
    ldy #0
    lda #SCREEN_BOX_V
    sta (progress_dst_ptr),y
    ldy #17
    sta (progress_dst_ptr),y
    dex
    bne sides

    lda progress_dst_ptr
    clc
    adc #40
    sta progress_dst_ptr
    bcc :+
    inc progress_dst_ptr+1
:
    ldy #0
    lda #SCREEN_BOX_BL
    sta (progress_dst_ptr),y
    iny
    lda #SCREEN_HLINE
bottom:
    sta (progress_dst_ptr),y
    iny
    cpy #17
    bcc bottom
    lda #SCREEN_BOX_BR
    sta (progress_dst_ptr),y
    rts
.endproc

; A = numer stacji, X = pierwsza kolumna tresci panelu ZRODLO/CEL.
;
; Szesc wierszy wewnatrz ramki ma stale, latwe do porownania znaczenie:
;   4: tytul (rysowany przez draw_main),
;   5: numer stacji i pojemnosc nominalna w KB,
;   6: pelna nazwa gestosci,
;   7: liczba sciezek oraz stron,
;   8: sektory/sciezke x bajty/sektor oraz liczba wszystkich sektorow,
;   9: wykryty protokol szybkiego SIO albo transmisja standardowa.
;
; Pojemnosc jest wyprowadzana z geometrii: dla sektorow 128/256/512 B liczba
; sektorow jest dzielona odpowiednio przez 8/4/2. Sa to nominalne wartosci
; uzywane przez Atari (90, 130, 180, 360, 520 i 720 KB); trzy startowe sektory
; po 128 B w formatach DD nie zmieniaja nazwy klasy nosnika.
.proc draw_selected_panel
    sta scan_index
    stx progress_render_rows

    lda #5
    jsr set_panel_cursor
    lda #'D'
    jsr ui_print_char
    lda scan_index
    jsr ui_print_u8

    ldx scan_index
    dex
    stx scan_index
    lda geo_present,x
    bne present
    lda #7
    jsr set_panel_cursor
    lda #<offline_label
    ldy #>offline_label
    jsr ui_print_z
    rts

present:
    ; Dwie spacje oddzielaja numer Dn od nominalnej pojemnosci.
    lda #' '
    jsr ui_print_char
    lda #' '
    jsr ui_print_char

    ldx scan_index
    jsr print_drive_capacity

    ; Nazwa gestosci. DD dwustronne dostaje jawny opis zatwierdzony dla
    ; wariantu A; liczba stron pozostaje dodatkowo widoczna w kolejnym wierszu.
    lda #6
    jsr set_panel_cursor
    ldx scan_index
    lda geo_bps_hi,x
    cmp #2
    bcs density_512
    cmp #1
    beq density_double
    lda geo_spt_lo,x
    cmp #26
    beq density_enhanced
    lda #<single_density_label
    ldy #>single_density_label
    bne print_density
density_enhanced:
    lda #<enhanced_density_label
    ldy #>enhanced_density_label
    bne print_density
density_double:
    lda geo_sides,x
    cmp #2
    bcc density_double_single
    lda #<double_sided_label
    ldy #>double_sided_label
    bne print_density
density_double_single:
    lda #<double_density_label
    ldy #>double_density_label
    bne print_density
density_512:
    lda #<sector_512_label
    ldy #>sector_512_label
print_density:
    jsr ui_print_z

    ; Czytelna geometria: np. "80 SC / 2 STR".
    lda #7
    jsr set_panel_cursor
    ldx scan_index
    lda geo_tracks,x
    jsr ui_print_u8
    lda #<tracks_label
    ldy #>tracks_label
    jsr ui_print_z
    ldx scan_index
    lda geo_sides,x
    jsr ui_print_u8
    lda #<sides_label
    ldy #>sides_label
    jsr ui_print_z

    ; Zwarty zapis sektora fizycznego i pelna liczba sektorow nosnika.
    lda #8
    jsr set_panel_cursor
    ldx scan_index
    lda geo_spt_lo,x
    ldy geo_spt_hi,x
    jsr ui_print_u16
    lda #'X'
    jsr ui_print_char
    ldx scan_index
    lda geo_bps_lo,x
    ldy geo_bps_hi,x
    jsr ui_print_u16
    lda #' '
    jsr ui_print_char
    lda #' '
    jsr ui_print_char
    ldx scan_index
    lda geo_total_lo,x
    ldy geo_total_hi,x
    jsr ui_print_u16
    lda #<sectors_short_label
    ldy #>sectors_short_label
    jsr ui_print_z

    ; Ostatni wiersz rozroznia SIO standardowe od rodziny turbo i pokazuje
    ; dzielnik POKEY, np. TURBO HXF9 albo TURBO US6.
    lda #9
    jsr set_panel_cursor
    ldx scan_index
    jsr print_drive_speed
    rts
.endproc

; Rzadziej wykonywane pomocnicze procedury mieszcza sie pod $3800. Ten obszar
; jest chroniony przez memory_takeover i nie odbiera miejsca glownemu kodowi.
.segment "AUXCODE"

; Oblicza i drukuje nominalna pojemnosc nosnika wskazanego w X. Dzielenie
; wykorzystuje przesuniecia: total/8 dla 128 B, /4 dla 256 B i /2 dla 512 B.
.proc print_drive_capacity
    lda geo_total_lo,x
    sta progress_src_ptr
    lda geo_total_hi,x
    sta progress_src_ptr+1
    lda geo_bps_hi,x
    cmp #2
    beq capacity_shift_1
    cmp #1
    beq capacity_shift_2
    lsr progress_src_ptr+1
    ror progress_src_ptr
capacity_shift_2:
    lsr progress_src_ptr+1
    ror progress_src_ptr
capacity_shift_1:
    lsr progress_src_ptr+1
    ror progress_src_ptr
    lda progress_src_ptr
    ldy progress_src_ptr+1
    jsr ui_print_u16
    lda #<kb_label
    ldy #>kb_label
    jmp ui_print_z
.endproc

; Drukuje stale dwuznakowe odstepy w wierszach opisujacych stacje.
.proc print_two_spaces
    lda #' '
    jsr ui_print_char
    jmp ui_print_char
.endproc

.segment "CODE"

; Drukuje nazwe wykrytej rodziny szybkiego SIO i dzielnik POKEY dla stacji X.
; Zero w geo_speed_kind oznacza transmisje standardowa.
.proc print_drive_speed
    stx scan_index
    lda geo_speed_kind,x
    beq speed_std
    pha
    lda #<turbo_prefix
    ldy #>turbo_prefix
    jsr ui_print_z
    pla
    cmp #1
    beq speed_us
    cmp #2
    beq speed_xf
    cmp #3
    beq speed_turbo
    cmp #4
    beq speed_warp
    lda #<hxf_label
    ldy #>hxf_label
    jsr ui_print_z
    jmp speed_value
speed_warp:
    lda #<warp_label
    ldy #>warp_label
    jsr ui_print_z
    jmp speed_value
speed_xf:
    lda #<xf_label
    ldy #>xf_label
    jsr ui_print_z
    jmp speed_value
speed_turbo:
    lda #<turbo_label
    ldy #>turbo_label
    jsr ui_print_z
    jmp speed_value
speed_us:
    lda #<us_label
    ldy #>us_label
    jsr ui_print_z
speed_value:
    ldx scan_index
    lda geo_speed_div,x
    jsr ui_print_u8
    rts
speed_std:
    lda #<std_label
    ldy #>std_label
    jmp ui_print_z
.endproc

; Ustaw wiersz A w zapamietanej kolumnie panelu. JSR do tej lokalnej trampoliny
; jest krotszy niz powtarzane LDX abs + JSR przy kazdym z pieciu wierszy.
set_panel_cursor:
    ldx progress_render_rows
    jmp ui_set_cursor

.proc draw_memory
    jsr memory_build_bank_list
    jsr ui_begin_screen
    lda #<memory_title
    ldy #>memory_title
    jsr ui_print_z
    jsr print_separator

    lda mem_sdx
    beq check_other_dos
    lda #<sdx_yes
    ldy #>sdx_yes
    jsr ui_print_z
    jmp show_mode
check_other_dos:
    lda mem_dos_present
    beq no_dos
    lda #<dos_yes
    ldy #>dos_yes
    jsr ui_print_z
    jmp show_mode
no_dos:
    lda #<sdx_no
    ldy #>sdx_no
    jsr ui_print_z

show_mode:
    lda mem_keep_dos
    beq memory_full_mode
    lda #<mode_keep
    ldy #>mode_keep
    jsr ui_print_z
    jmp show_values
memory_full_mode:
    lda #<mode_full
    ldy #>mode_full
    jsr ui_print_z

show_values:
    lda #<main_free_label
    ldy #>main_free_label
    jsr ui_print_z
    lda mem_main_free_lo
    ldy mem_main_free_hi
    jsr ui_print_u16
    jsr ui_print_eol

    lda #<free_banks_label
    ldy #>free_banks_label
    jsr ui_print_z
    lda mem_free_banks
    jsr ui_print_u8
    jsr ui_print_eol

    lda #<usable_banks_label
    ldy #>usable_banks_label
    jsr ui_print_z
    lda mem_usable_banks
    jsr ui_print_u8
    jsr ui_print_eol

    lda #<total_banks_label
    ldy #>total_banks_label
    jsr ui_print_z
    lda mem_total_banks
    jsr ui_print_u8
    jsr ui_print_eol

    lda #<pbmask_label
    ldy #>pbmask_label
    jsr ui_print_z
    lda mem_pbmask
    jsr print_hex
    jsr ui_print_eol
    jsr ui_print_eol

    lda mem_buffer_units_hi
    cmp #$16
    bcc no_one_pass
    bne memory_one_pass
    lda mem_buffer_units_lo
    cmp #$7D
    bcc no_one_pass
memory_one_pass:
    lda #<one_pass_yes
    ldy #>one_pass_yes
    jsr ui_print_z
    jmp wait_key
no_one_pass:
    lda #<one_pass_no
    ldy #>one_pass_no
    jsr ui_print_z
wait_key:
    lda #<return_label
    ldy #>return_label
    jmp ui_print_z
.endproc

.proc do_copy
    lda source_drive
    jsr probe_drive
    lda target_drive
    jsr probe_drive

    lda source_drive
    sta copy_source
    lda target_drive
    sta copy_target
    jsr copy_prepare
    bcc :+
    jmp show_error
:
    ; Napisy etapow sa w RAM-ie, mimo ze linker grupuje je jako RODATA. Jeden
    ; bajt zmieniany przed startem pozwala zachowac identyczne wycentrowanie:
    ; bez weryfikacji ekran pokazuje 1/2 i 2/2, z weryfikacja 1/3, 2/3, 3/3.
    ; verify_enabled ma zawsze wartosc 0 albo 1, wiec po dodaniu kodu znaku
    ; '2' otrzymujemy bez rozgalezienia odpowiednio '2' lub '3'.
    lda verify_enabled
    clc
    adc #'2'
    sta copy_reading+17
    sta copy_writing+17
    lda #0
    sta target_initialized

    jsr draw_copy_confirmation
    jsr ui_wait_start_select
    bcs read_disk
    jmp cancelled

read_disk:
    jsr ui_begin_screen
    jsr ui_colors_read
    jsr print_chunk_range
    lda #<copy_reading
    ldy #>copy_reading
    jsr ui_print_z
    jsr copy_progress_init
    jsr copy_read_all
    bcc :+
    jmp show_error
:

    lda target_initialized
    beq first_target
    jmp target_already_initialized

first_target:
    jsr begin_media_prompt
    lda #<copy_insert_target
    ldy #>copy_insert_target
    jsr ui_print_z
    lda target_drive
    jsr ui_print_u8
    jsr ui_print_eol
    lda #<copy_last_warning
    ldy #>copy_last_warning
    jsr ui_print_z
    lda #<continue_prompt
    ldy #>continue_prompt
    jsr ui_print_z
    jsr ui_wait_start_select
    bcs :+
    jmp cancelled
:
    lda format_enabled
    beq check_preformatted
    jmp format_target

check_preformatted:
    lda target_drive
    jsr probe_drive
    jsr copy_validate_target
    bcc :+
    jmp target_retry_error
:
    jmp target_ready

format_target:
    lda target_drive
    jsr probe_drive
    bcc target_present
    lda #2
    sta copy_error_kind
    jmp target_retry_error
target_present:
    jsr ui_begin_screen
    jsr ui_colors_write
    lda #<copy_formatting
    ldy #>copy_formatting
    jsr ui_print_z
    jsr copy_format_target
    bcc format_complete
    jmp target_retry_error
format_complete:
    jsr print_hyperxf_format_mode
    jsr ui_delay_notice
    jmp target_ready
target_ready:
    lda #1
    sta target_initialized
    jmp write_disk

target_already_initialized:
    lda source_drive
    cmp target_drive
    bne write_disk

    ; Jedna fizyczna stacja wymaga ponownej zmiany na cel dla kazdej porcji.
    jsr begin_media_prompt
    lda #<copy_insert_target
    ldy #>copy_insert_target
    jsr ui_print_z
    lda target_drive
    jsr ui_print_u8
    lda #<continue_prompt
    ldy #>continue_prompt
    jsr ui_print_z
    jsr ui_wait_start_select
    bcs recheck_target
    jmp cancelled
recheck_target:
    lda target_drive
    jsr probe_drive
    jsr copy_validate_target
    bcc :+
    jmp target_retry_error
:

write_disk:
    jsr ui_begin_screen
    jsr ui_colors_write
    jsr print_chunk_range
    lda #<copy_writing
    ldy #>copy_writing
    jsr ui_print_z
    jsr copy_progress_init
    jsr copy_write_all
    bcc :+
    jmp target_retry_error
:

    lda verify_enabled
    beq chunk_complete
    jsr ui_begin_screen
    jsr ui_colors_verify
    jsr print_chunk_range
    lda #<copy_verifying
    ldy #>copy_verifying
    jsr ui_print_z
    jsr copy_progress_init
    jsr copy_verify_all
    bcc :+
    jmp target_retry_error
:

chunk_complete:
    jsr copy_advance_chunk
    bcs copy_finished

    lda source_drive
    cmp target_drive
    beq source_swap
    jmp read_disk

source_swap:
    ; Przed odczytem nastepnej porcji trzeba ponownie wlozyc dysk zrodlowy.
    jsr begin_media_prompt
    lda #<copy_insert_source_next
    ldy #>copy_insert_source_next
    jsr ui_print_z
    lda source_drive
    jsr ui_print_u8
    lda #<continue_prompt
    ldy #>continue_prompt
    jsr ui_print_z
    jsr ui_wait_start_select
    bcs recheck_source
    jmp cancelled
recheck_source:
    lda source_drive
    jsr probe_drive
    jsr copy_validate_source
    bcc :+
    jmp show_error
:
    jmp read_disk

copy_finished:
    jsr ui_begin_screen
    lda verify_enabled
    beq success_without_verify
    lda #<copy_success
    ldy #>copy_success
    jsr ui_print_z
    jmp success_wait
success_without_verify:
    lda #<copy_success_no_verify
    ldy #>copy_success_no_verify
    jsr ui_print_z
success_wait:
    ; Tylko kopia jednoprzebiegowa pozostawia w bankach kompletna dyskietke.
    ; Po START resetujemy zakres sektorow, ale nie bufor, i przechodzimy od razu
    ; do przygotowania nowego celu. SELECT wraca do menu. W trybie wieloporcjowym
    ; bufor zawiera jedynie ostatnia porcje, wiec ponowny zapis bylby bledem.
    lda copy_single_pass
    beq success_return
    lda #<next_copy_insert
    ldy #>next_copy_insert
    jsr ui_print_z
    lda target_drive
    jsr ui_print_u8
    jsr ui_print_eol
    lda #<next_copy_choices
    ldy #>next_copy_choices
    jsr ui_print_z
    jsr ui_wait_start_select
    bcc cancelled
    jsr copy_begin_chunks
    lda #0
    sta target_initialized
    lda format_enabled
    bne repeat_with_format
    jmp check_preformatted
repeat_with_format:
    jmp format_target
success_return:
    lda #<return_label
    ldy #>return_label
    jsr ui_print_z
    jsr ui_wait_key
cancelled:
    rts

show_error:
    jsr draw_copy_error
    lda #<return_label
    ldy #>return_label
    jsr ui_print_z
    jsr ui_wait_key
    rts

.segment "UICODE"
retry_target_prompt:
    .byte ATASCII_EOL, "R-PONOW ZAPIS Z BUFORA", ATASCII_EOL
    .byte "F-FORMAT+ZAPIS  Q/ESC-ANULUJ", 0

; Ten tekst jest tylko stala, ale trzymamy go w wolnej koncowce UICODE,
; oszczedzajac ciasny obszar glownego kodu ponizej $A000.
::main_free_label:
    .byte "RAM GLOWNY: ", 0
::tracks_label:
    .byte " SC / ", 0
::sides_label:
    .byte " STR", 0

target_retry_error:
    jsr draw_copy_error
    lda #<retry_target_prompt
    ldy #>retry_target_prompt
    jsr ui_print_z
    jsr ui_delay_notice
wait_retry_key:
    jsr ui_get_key_upper
    cmp #'R'
    beq retry_write
    cmp #'F'
    beq retry_format
    cmp #'Q'
    beq retry_cancel
    cmp #ATASCII_ESC
    bne wait_retry_key
retry_cancel:
    rts
retry_format:
    jmp format_target
retry_write:
    lda #1
    sta target_initialized
    jmp write_disk
.segment "CODE"
.endproc

; Po FORMAT ostatnia wartosc MYSPEED dotyczy wlasnie rozkazu $21/$22. Dla
; rozpoznanego HyperXF pokazujemy zatem nie zalozony profil, lecz tryb faktycznie
; uzyty po wszystkich ponowieniach. Oprogramowanie stacji wybiera przeplot
; sektorow UltraSpeed tylko wtedy, gdy sama komenda formatowania nadeszla
; szybko.
.proc print_hyperxf_format_mode
    ldx target_drive
    dex
    lda geo_speed_kind,x
    cmp #5
    bne done
    lda sio_actual_mode
    cmp #40
    beq standard_skew
    lda #<hyperxf_format_ultra
    ldy #>hyperxf_format_ultra
    jmp ui_print_z
standard_skew:
    lda #<hyperxf_format_standard
    ldy #>hyperxf_format_standard
    jmp ui_print_z
done:
    rts
.endproc

.proc print_separator
    ; Zostaw jedna kolumne przed RMARGN. Wypelnienie calego logicznego wiersza
    ; uruchamia automatyczne zawijanie E: i przygotowanie dolnego wiersza
    ; edytora, co usuneloby dolna krawedz ramki semigraficznej.
    lda #37
    sta scan_index
loop:
    lda #ATASCII_ESC
    jsr ui_print_char
    lda #$12
    jsr ui_print_char
    dec scan_index
    bne loop
    jmp ui_print_eol
.endproc

.proc print_format_state
    lda #<format_label
    ldy #>format_label
    jsr ui_print_z
    lda format_enabled
    beq no_format
    lda #<format_same_label
    ldy #>format_same_label
    jmp ui_print_z
no_format:
    lda #<format_no_label
    ldy #>format_no_label
    jmp ui_print_z
.endproc

.proc print_chunk_range
    lda #<copy_chunk_label
    ldy #>copy_chunk_label
    jsr ui_print_z
    lda copy_pass_number
    jsr ui_print_u8
    lda #<copy_range_label
    ldy #>copy_range_label
    jsr ui_print_z
    lda copy_chunk_start_lo
    ldy copy_chunk_start_hi
    jsr ui_print_u16
    lda #'-'
    jsr ui_print_char
    lda copy_chunk_end_lo
    ldy copy_chunk_end_hi
    jsr ui_print_u16
    jmp ui_print_eol
.endproc

.proc begin_media_prompt
    jsr ui_begin_screen
    lda #<media_prompt_title
    ldy #>media_prompt_title
    jsr ui_print_z
    jmp print_separator
.endproc

; Rysuje szeroka ramke o stalej szerokosci 36 znakow. A/Y zawiera przesuniecie
; lewego gornego rogu wzgledem SAVMSC, a X liczbe pustych wierszy wewnatrz.
; Procedura sluzy ekranowi PARAMETRY KOPII i nie korzysta z CIO, dzieki czemu
; naroza oraz pionowe krawedzie trafiaja zawsze do dokladnych kolumn ekranu.
.proc draw_wide_box
    stx progress_render_rows
    clc
    adc SAVMSC
    sta progress_dst_ptr
    tya
    adc SAVMSC+1
    sta progress_dst_ptr+1

    ldy #0
    lda #SCREEN_BOX_TL
    sta (progress_dst_ptr),y
    iny
    lda #SCREEN_HLINE
top:
    sta (progress_dst_ptr),y
    iny
    cpy #35
    bcc top
    lda #SCREEN_BOX_TR
    sta (progress_dst_ptr),y

sides:
    jsr wide_box_next_row
    ldy #0
    lda #SCREEN_BOX_V
    sta (progress_dst_ptr),y
    ldy #35
    sta (progress_dst_ptr),y
    dec progress_render_rows
    bne sides

    jsr wide_box_next_row
    ldy #0
    lda #SCREEN_BOX_BL
    sta (progress_dst_ptr),y
    iny
    lda #SCREEN_HLINE
bottom:
    sta (progress_dst_ptr),y
    iny
    cpy #35
    bcc bottom
    lda #SCREEN_BOX_BR
    sta (progress_dst_ptr),y
    rts

wide_box_next_row:
    lda progress_dst_ptr
    clc
    adc #40
    sta progress_dst_ptr
    bcc :+
    inc progress_dst_ptr+1
:
    rts
.endproc

.proc draw_copy_confirmation
    jsr ui_begin_screen

    ; Wariant C: dwa szerokie bloki rozdzielaja wybor nosnikow od informacji
    ; o geometrii i pamieci. Wszystkie wartosci pochodza z tego samego rekordu
    ; geometrii, ktory zostanie przekazany procedurom kopiowania.
    lda #<(3*40+2)
    ldy #>(3*40+2)
    ldx #2
    jsr draw_wide_box
    lda #<(8*40+2)
    ldy #>(8*40+2)
    ldx #4
    jsr draw_wide_box

    lda #1
    ldx #12
    jsr ui_set_cursor
    lda #<copy_title
    ldy #>copy_title
    jsr ui_print_z

    lda #3
    ldx #13
    jsr ui_set_cursor
    lda #<confirm_media_title
    ldy #>confirm_media_title
    jsr ui_print_z

    lda #4
    ldx #3
    jsr ui_set_cursor
    lda #<copy_from_label
    ldy #>copy_from_label
    jsr ui_print_z
    lda source_drive
    jsr ui_print_u8
    jsr print_two_spaces
    ldx source_drive
    dex
    jsr print_drive_capacity
    jsr print_two_spaces
    ldx source_drive
    dex
    jsr print_drive_speed

    lda #5
    ldx #3
    jsr ui_set_cursor
    lda #<copy_to_label
    ldy #>copy_to_label
    jsr ui_print_z
    lda target_drive
    jsr ui_print_u8
    jsr print_two_spaces
    ldx target_drive
    dex
    jsr print_drive_capacity
    jsr print_two_spaces
    ldx target_drive
    dex
    jsr print_drive_speed

    lda #8
    ldx #11
    jsr ui_set_cursor
    lda #<confirm_data_title
    ldy #>confirm_data_title
    jsr ui_print_z

    lda #9
    ldx #4
    jsr ui_set_cursor
    lda #<confirm_geometry_label
    ldy #>confirm_geometry_label
    jsr ui_print_z
    ldx source_drive
    dex
    lda geo_tracks,x
    jsr ui_print_u8
    lda #'X'
    jsr ui_print_char
    ldx source_drive
    dex
    lda geo_sides,x
    jsr ui_print_u8
    lda #'X'
    jsr ui_print_char
    ldx source_drive
    dex
    lda geo_spt_lo,x
    ldy geo_spt_hi,x
    jsr ui_print_u16
    lda #<confirm_geometry_sep
    ldy #>confirm_geometry_sep
    jsr ui_print_z
    ldx source_drive
    dex
    lda geo_bps_lo,x
    ldy geo_bps_hi,x
    jsr ui_print_u16
    lda #<confirm_bytes_suffix
    ldy #>confirm_bytes_suffix
    jsr ui_print_z

    lda #10
    ldx #4
    jsr ui_set_cursor
    lda #<confirm_sectors_label
    ldy #>confirm_sectors_label
    jsr ui_print_z
    ldx source_drive
    dex
    lda geo_total_lo,x
    ldy geo_total_hi,x
    jsr ui_print_u16

    lda #11
    ldx #4
    jsr ui_set_cursor
    lda #<confirm_buffer_label
    ldy #>confirm_buffer_label
    jsr ui_print_z
    lda copy_required_banks
    jsr ui_print_u8
    lda #'/'
    jsr ui_print_char
    lda mem_usable_banks
    jsr ui_print_u8

    lda #12
    ldx #4
    jsr ui_set_cursor
    lda #<confirm_passes_label
    ldy #>confirm_passes_label
    jsr ui_print_z
    lda copy_single_pass
    beq confirm_multi_pass
    lda #<confirm_one_pass
    ldy #>confirm_one_pass
    jsr ui_print_z
    jmp confirm_pass_done
confirm_multi_pass:
    lda #<confirm_many_passes
    ldy #>confirm_many_passes
    jsr ui_print_z
confirm_pass_done:

    lda #15
    ldx #4
    jsr ui_set_cursor
    jsr print_format_state

    lda #16
    ldx #4
    jsr ui_set_cursor
    lda #<verify_label
    ldy #>verify_label
    jsr ui_print_z
    lda verify_enabled
    beq confirm_verify_no
    lda #<yes_label
    ldy #>yes_label
    jsr ui_print_z
    jmp confirm_verify_done
confirm_verify_no:
    lda #<no_label
    ldy #>no_label
    jsr ui_print_z
confirm_verify_done:

    lda #18
    ldx #4
    jsr ui_set_cursor
    lda #<copy_warning_overwrite
    ldy #>copy_warning_overwrite
    jsr ui_print_z
    lda #19
    ldx #8
    jsr ui_set_cursor
    lda #<copy_warning_deleted
    ldy #>copy_warning_deleted
    jsr ui_print_z

    lda #21
    ldx #3
    jsr ui_set_cursor
    lda #<(continue_prompt+1)
    ldy #>(continue_prompt+1)
    jmp ui_print_z
.endproc

.proc draw_copy_error
    jsr ui_begin_screen
    lda #<copy_error_title
    ldy #>copy_error_title
    jsr ui_print_z
    jsr print_separator
    lda #<copy_error_label
    ldy #>copy_error_label
    jsr ui_print_z
    lda copy_error_kind
    jsr ui_print_u8
    lda #<copy_error_sector_label
    ldy #>copy_error_sector_label
    jsr ui_print_z
    lda copy_error_sector_lo
    ldy copy_error_sector_hi
    jsr ui_print_u16
    lda #<copy_error_sio_label
    ldy #>copy_error_sio_label
    jsr ui_print_z
    lda copy_error_status
    jsr ui_print_u8
    jsr ui_print_eol
    lda #<copy_error_help
    ldy #>copy_error_help
    jmp ui_print_z
.endproc

.proc copy_ui_progress
    ; Licznik sektora jest zapisywany bezposrednio do RAM ekranu. Cztery
    ; wywolania CIO na kazdy sektor byly niewidocznie drogie i wraz z kopiowaniem
    ; bufora zjadaly margines czasowy przeplotu HyperXF UltraSpeed.
    lda SAVMSC
    clc
    adc #<(PROGRESS_NUMBER_ROW*40+PROGRESS_NUMBER_COL)
    sta progress_dst_ptr
    lda SAVMSC+1
    adc #>(PROGRESS_NUMBER_ROW*40+PROGRESS_NUMBER_COL)
    sta progress_dst_ptr+1
    ldy #0
    lda copy_current_hi
    jsr store_hex_screen
    lda copy_current_lo
    jsr store_hex_screen

    ; MYSPEED=$28 (40) oznacza, ze konkretna operacja zakonczyla sie w trybie
    ; standardowym. Kazda inna wartosc to aktywna rodzina turbo. Ten wskaznik
    ; ujawnia cichy powrot sterownika do standardu, ktorego sam napis HXF9/US9
    ; w menu nie potrafi rozpoznac. Kody znakow sa kodami ekranowymi, nie
    ; ATASCII.
    ldy #PROGRESS_SPEED_COL-PROGRESS_NUMBER_COL
    lda sio_actual_mode
    cmp #40
    beq show_standard
    lda #'F'-$20
    sta (progress_dst_ptr),y
    iny
    lda #'A'-$20
    sta (progress_dst_ptr),y
    iny
    lda #'S'-$20
    sta (progress_dst_ptr),y
    iny
    lda #'T'-$20
    sta (progress_dst_ptr),y
    jmp speed_done
show_standard:
    lda #'S'-$20
    sta (progress_dst_ptr),y
    iny
    lda #'T'-$20
    sta (progress_dst_ptr),y
    iny
    lda #'D'-$20
    sta (progress_dst_ptr),y
    iny
    lda #0
    sta (progress_dst_ptr),y
speed_done:

    jsr render_sector_atascii
    jsr set_progress_bar_ptr

    ; Gorny pasek przedstawia sektory aktualnej logicznej sciezki. Pozycja
    ; jest utrzymywana niezaleznie od granic porcji bufora. Przy poczatku
    ; nowej sciezki czyscimy 32 pola i zerujemy skaler. Sam skaler rozklada
    ; 18 albo 26 sektorow na cala szerokosc paska, wiec prawa krawedz zostaje
    ; osiagnieta dokladnie wraz z ostatnim sektorem sciezki.
    lda progress_track_pos
    bne track_ready
    jsr clear_progress_track
    lda #TRACK_BAR_OFFSET
    sta progress_track_cell
    lda #0
    sta progress_track_accum
track_ready:
    jsr advance_track_progress
    inc progress_track_pos
    lda progress_track_pos
    cmp progress_track_spt
    bcc update_whole_disk
    lda #0
    sta progress_track_pos
update_whole_disk:
    jmp update_disk_progress
.endproc

; Dolny pasek narasta przez cala dyskietke. Dzielnik jest wyliczany raz na
; ekran jako ceil(total/32); w goracej petli wykonujemy tylko inkrementacje i
; jedno porownanie, aby wizualizacja nie psula przeplotu szybkiej HyperXF.
; Procedura lezy w UICODE ponizej wspolnego bufora sektorowego $3E00.
.segment "UICODE"
.proc update_disk_progress
    lda progress_disk_cell
    cmp #32
    bcc disk_cell_ready
    lda #31
disk_cell_ready:
    clc
    adc #DISK_BAR_OFFSET
    tay
    lda #SCREEN_PROGRESS
    sta (progress_dst_ptr),y

    inc probe_status0
    lda probe_status0
    cmp progress_disk_step
    bcc done
    lda #0
    sta probe_status0
    inc progress_disk_cell
done:
    rts
.endproc
.segment "CODE"

.proc copy_progress_init
    lda #PROGRESS_NUMBER_ROW
    ldx #10
    jsr ui_set_cursor
    lda #<progress_sector_label
    ldy #>progress_sector_label
    jsr ui_print_z
    lda copy_chunk_start_hi
    jsr print_hex
    lda copy_chunk_start_lo
    jsr print_hex
    lda #<progress_total_sep
    ldy #>progress_total_sep
    jsr ui_print_z
    lda copy_total_hi
    jsr print_hex
    lda copy_total_lo
    jsr print_hex

    lda #PROGRESS_NUMBER_ROW
    ldx #31
    jsr ui_set_cursor
    lda #<progress_sio_label
    ldy #>progress_sio_label
    jsr ui_print_z

    ; Nazwa etapu zajmuje jednolity pasek w negatywie, a zawartosc sektora
    ; pozostaje glownym elementem wizualizacji. Modyfikujemy bezposrednio kody
    ; ekranowe.
    lda SAVMSC
    clc
    adc #<(2*40+1)
    sta progress_dst_ptr
    lda SAVMSC+1
    adc #>(2*40+1)
    sta progress_dst_ptr+1
    ldy #37
invert_stage:
    lda (progress_dst_ptr),y
    ora #$80
    sta (progress_dst_ptr),y
    dey
    bpl invert_stage

    jsr set_progress_bar_ptr
    jsr clear_progress_bars
    jsr init_track_progress
    jsr init_disk_progress
    sta probe_status0
    stx progress_disk_cell

    ; Przy kolejnym przebiegu bufora wypelnij czesc dolnego paska nalezaca do
    ; sektorow zakonczonych we wczesniejszych porcjach.
    txa
    beq initialized
    clc
    adc #DISK_BAR_OFFSET-1
    tay
    lda #SCREEN_PROGRESS
fill_disk_prefix:
    sta (progress_dst_ptr),y
    dey
    cpy #DISK_BAR_OFFSET-1
    bne fill_disk_prefix
initialized:
    rts
.endproc

.proc set_progress_bar_ptr
    lda SAVMSC
    clc
    adc #<(PROGRESS_BAR_ROW*40+PROGRESS_BAR_COL)
    sta progress_dst_ptr
    lda SAVMSC+1
    adc #>(PROGRESS_BAR_ROW*40+PROGRESS_BAR_COL)
    sta progress_dst_ptr+1
    rts
.endproc

.segment "AUXCODE"
.proc clear_progress_bars
    jsr clear_progress_track

    ; Drugi wiersz jest o 40 bajtow dalej od tego samego wskaznika ekranu.
    ldy #DISK_BAR_OFFSET+31
    lda #SCREEN_HLINE
clear_disk:
    sta (progress_dst_ptr),y
    dey
    cpy #DISK_BAR_OFFSET-1
    bne clear_disk

    ; S = biezaca sciezka, D = cala dyskietka. Litery sa w negatywie, aby
    ; jednoznacznie odcinac etykiete od cienkiej linii pustej czesci paska.
    ldy #0
    lda #('S'-$20)|$80
    sta (progress_dst_ptr),y
    ldy #DISK_LABEL_OFFSET
    lda #('D'-$20)|$80
    sta (progress_dst_ptr),y
    rts
.endproc

; Ustal pozycje pierwszego paska dla poczatku aktualnej porcji. Wspolna
; procedura dzielenia zwraca reszte (chunk_start-1) modulo sectors/track.
.proc init_track_progress
    lda copy_chunk_start_lo
    sec
    sbc #1
    sta progress_src_ptr
    lda copy_chunk_start_hi
    sbc #0
    sta progress_src_ptr+1
    ldx source_drive
    dex
    lda geo_spt_lo,x
    sta progress_track_spt
    sta progress_divisor
    jsr progress_divide_16_8
    sta progress_track_pos

    ; cycle_start i probe_status3 nie sa juz potrzebne po wyborze stacji oraz
    ; sondowaniu geometrii. Podczas kopiowania sluza odpowiednio jako indeks
    ; nastepnego pola paska i reszta skalera Bresenhama.
    lda #TRACK_BAR_OFFSET
    sta progress_track_cell
    lda #0
    sta progress_track_accum

    ; Przy porcji zaczynajacej sie w srodku sciezki odtworz stan paska przez
    ; wykonanie skalera dla zakonczonych juz sektorow. Jawne LDA przed BEQ jest
    ; konieczne, poniewaz STA nie zmienia flag 6502, a flaga Z pozostawiona
    ; przez dzielenie nie opisuje zapisanej pozycji paska.
    lda progress_track_pos
    beq done
    tax
fill_prefix:
    jsr advance_track_progress
    dex
    bne fill_prefix
done:
    rts
.endproc

; Rozloz jeden sektor biezacej sciezki na pasek szerokosci 32 znakow.
; Do reszty dodajemy 32 i odejmujemy liczbe sektorow na sciezke; kazde
; odejmowanie zapala jedno pole. Dla 18 SPT powstaje 1 albo 2 pola na sektor,
; dla 26 SPT rowniez 1 albo 2. Po ostatnim sektorze zawsze swieca wszystkie
; 32 pola, bez dzielenia w goracej petli SIO.
.proc advance_track_progress
    lda progress_track_accum
    clc
    adc #32
next_cell:
    cmp progress_track_spt
    bcc save_remainder
    ; CMP ustawilo znacznik C, wiec SBC odejmuje bez pozyczki.
    sbc progress_track_spt
    pha
    ldy progress_track_cell
    lda #SCREEN_PROGRESS
    sta (progress_dst_ptr),y
    inc progress_track_cell
    pla
    jmp next_cell
save_remainder:
    sta progress_track_accum
    rts
.endproc
.segment "CODE"

.proc render_sector_atascii
    lda #<sio_sector_buf
    sta progress_src_ptr
    lda #>sio_sector_buf
    sta progress_src_ptr+1

    ldx #0
    lda sio_length_hi
    beq geometry_ready
    inx
    cmp #1
    beq geometry_ready
    inx
geometry_ready:
    lda progress_rows,x
    sta progress_render_rows
    lda SAVMSC
    clc
    adc progress_offset_lo,x
    sta progress_dst_ptr
    lda SAVMSC+1
    adc progress_offset_hi,x
    sta progress_dst_ptr+1

row_loop:
    ldy #0
byte_loop:
    lda (progress_src_ptr),y
    tax
    lda atascii_screen_table,x
    sta (progress_dst_ptr),y
    iny
    cpy #32
    bcc byte_loop

    lda progress_src_ptr
    clc
    adc #32
    sta progress_src_ptr
    bcc :+
    inc progress_src_ptr+1
:
    lda progress_dst_ptr
    clc
    adc #40
    sta progress_dst_ptr
    bcc :+
    inc progress_dst_ptr+1
:
    dec progress_render_rows
    bne row_loop
    rts
.endproc

; A = bajt, Y = pozycja w wierszu. Zapisuje dwie cyfry szesnastkowe jako kody
; ekranowe i zwieksza Y o dwa. Procedura nie korzysta z CIO ani kursora E:.
.proc store_hex_screen
    pha
    lsr
    lsr
    lsr
    lsr
    jsr nibble_to_screen
    sta (progress_dst_ptr),y
    iny
    pla
    and #$0F
    jsr nibble_to_screen
    sta (progress_dst_ptr),y
    iny
    rts
.endproc

.proc nibble_to_screen
    cmp #10
    bcc decimal_digit
    ; Po CMP znacznik C=1: 10+$16+1=$21, czyli kod ekranowy litery A.
    adc #$16
    rts
decimal_digit:
    ora #$10                    ; kody ekranowe cyfr 0..9 to $10..$19
    rts
.endproc

; Wyswietla A jako dwie cyfry szesnastkowe.
.proc print_hex
    pha
    lsr
    lsr
    lsr
    lsr
    jsr print_nibble
    pla
    and #$0F
print_nibble:
    cmp #10
    bcc digit
    clc
    adc #'A'-10
    jmp ui_print_char
digit:
    ora #'0'
    jmp ui_print_char
.endproc

; Ograniczenie programu do osmiu stacji zmniejsza tablice geometrii i zostawia
; wolne $392C-$3984. Umieszczamy tu rzadko wykonywane przygotowanie paskow,
; zachowujac cale $4000-$7FFF na bankowany bufor i kod glowny ponizej $A000.
.segment "LOWCODE"

.proc clear_progress_track
    ldy #TRACK_BAR_OFFSET+31
    lda #SCREEN_HLINE
loop:
    sta (progress_dst_ptr),y
    dey
    cpy #TRACK_BAR_OFFSET-1
    bne loop
    rts
.endproc

; Dzielenie 16-bitowej liczby w progress_src_ptr przez 8-bitowy dzielnik.
; Zwraca iloraz w X i reszte w mlodszym bajcie progress_src_ptr. Maksymalny
; potrzebny iloraz to 231 (4160/18), wiec osiem bitow wystarcza.
.proc progress_divide_16_8
    ldx #0
loop:
    lda progress_src_ptr+1
    bne subtract
    lda progress_src_ptr
    cmp progress_divisor
    bcc done
subtract:
    lda progress_src_ptr
    sec
    sbc progress_divisor
    sta progress_src_ptr
    bcs no_borrow
    dec progress_src_ptr+1
no_borrow:
    inx
    bne loop
done:
    rts
.endproc

; Przygotuj dolny pasek. Krok ceil(total/32) miesci sie w bajcie dla wszystkich
; obslugiwanych geometrii Atari (maksimum 4160 sektorow). Zwraca w X numer
; komorki odpowiadajacej poczatkowi porcji, a w A reszte do dalszego zliczania.
.proc init_disk_progress
    lda copy_total_lo
    clc
    adc #31
    sta progress_src_ptr
    lda copy_total_hi
    adc #0
    sta progress_src_ptr+1
    ldx #5
shift:
    lsr progress_src_ptr+1
    ror progress_src_ptr
    dex
    bne shift
    lda progress_src_ptr
    sta progress_disk_step
    sta progress_divisor

    lda copy_chunk_start_lo
    sec
    sbc #1
    sta progress_src_ptr
    lda copy_chunk_start_hi
    sbc #0
    sta progress_src_ptr+1
    jsr progress_divide_16_8
    rts
.endproc

.segment "CODE"

.segment "RUNAD"
    .word start
