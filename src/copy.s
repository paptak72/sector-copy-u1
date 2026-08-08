.include "os.inc"

; ---------------------------------------------------------------------------
; Silnik kopiowania sektorowego
; ---------------------------------------------------------------------------
;
; Modul nie wyswietla menu i nie pyta o dyskietki. Otrzymuje numery stacji
; copy_source/copy_target oraz profile geometry.s, po czym wykonuje dokladnie
; jedna z operacji: przygotowanie, odczyt porcji, format, zapis lub porownanie.
; Postep przekazuje do main.s przez copy_ui_progress po kazdym sektorze.
;
; Bufor jest liczony w jednostkach 128 bajtow. Dzieki temu algorytm porcji nie
; rozcina sektora na granicy banku i poprawnie miesza trzy sektory startowe
; 128 B z dalszymi sektorami 256/512 B. copy_chunk_start/end sa numerami
; logicznymi wlacznie; copy_advance_chunk rozpoczyna nastepna porcje od end+1.
;
; Kody bledow sa rozdzielone na rodzaj, sektor i status SIO. Warstwa glowna
; moze zatem odroznic np. brak pamieci od bledu zapisu konkretnego sektora i
; zaoferowac bezpieczne ponowienie z zachowanego bufora.

.import geo_present
.import geo_bps_lo
.import geo_bps_hi
.import geo_tracks
.import geo_sides
.import geo_spt_lo
.import geo_spt_hi
.import geo_density
.import geo_percom_ok
.import geo_total_lo
.import geo_total_hi

.import mem_usable_banks
.import mem_buffer_units_lo
.import mem_buffer_units_hi
.import memory_build_bank_list

.import buffer_reset
.import buffer_store
.import buffer_load
.import buffer_compare

.import sio_read_sector
.import sio_write_sector
.import sio_write_percom
.import sio_format_disk
.import sio_result
.import sio_sector_buf
.import sio_sector_lo
.import sio_sector_hi
.import sio_length_lo
.import sio_length_hi
.import sio_percom_buf
.import sio_format_command

.import copy_ui_progress

.export copy_prepare
.export copy_validate_target
.export copy_validate_source
.export copy_begin_chunks
.export copy_advance_chunk
.export copy_read_all
.export copy_write_all
.export copy_verify_all
.export copy_format_target
.export copy_source
.export copy_target
.export copy_required_banks
.export copy_single_pass
.export copy_error_kind
.export copy_error_sector_lo
.export copy_error_sector_hi
.export copy_error_status
.export copy_current_lo
.export copy_current_hi
.export copy_total_lo
.export copy_total_hi
.export copy_chunk_start_lo
.export copy_chunk_start_hi
.export copy_chunk_end_lo
.export copy_chunk_end_hi
.export copy_pass_number

COPY_OK             = 0
COPY_NO_SOURCE      = 1
COPY_NO_TARGET      = 2
COPY_GEOMETRY       = 3
COPY_NO_MEMORY      = 4
COPY_READ_ERROR     = 5
COPY_WRITE_ERROR    = 6
COPY_VERIFY_IO      = 7
COPY_VERIFY_DATA    = 8
COPY_BUFFER_ERROR   = 9
COPY_FORMAT_ERROR   = 10

.segment "BSS"
copy_source:          .res 1
copy_target:          .res 1
copy_required_banks:  .res 1
copy_single_pass:     .res 1
copy_required_units_lo: .res 1
copy_required_units_hi: .res 1
copy_error_kind:      .res 1
copy_error_sector_lo: .res 1
copy_error_sector_hi: .res 1
copy_error_status:    .res 1
copy_current_lo:      .res 1
copy_current_hi:      .res 1
copy_total_lo:        .res 1
copy_total_hi:        .res 1
copy_bps_lo:          .res 1
copy_bps_hi:          .res 1
copy_tracks:          .res 1
copy_sides:           .res 1
copy_spt_lo:          .res 1
copy_spt_hi:          .res 1
copy_density:         .res 1
copy_percom_ok:       .res 1
copy_source_index:    .res 1
copy_target_index:    .res 1
copy_units_lo:        .res 1
copy_units_hi:        .res 1
copy_retry:           .res 1
copy_chunk_start_lo:  .res 1
copy_chunk_start_hi:  .res 1
copy_chunk_end_lo:    .res 1
copy_chunk_end_hi:    .res 1
copy_pass_number:     .res 1
copy_capacity_lo:     .res 1
copy_capacity_hi:     .res 1
copy_used_lo:         .res 1
copy_used_hi:         .res 1
copy_candidate_lo:    .res 1
copy_candidate_hi:    .res 1
copy_sector_units:    .res 1

.segment "CODE"

; Validates both selected drives, geometry and buffer capacity.
; copy_source/copy_target must contain unit numbers 1..8.
; Carry clear on success, set on failure; copy_error_kind gives the reason.
.proc copy_prepare
    lda #COPY_OK
    sta copy_error_kind
    sta copy_error_sector_lo
    sta copy_error_sector_hi
    sta copy_error_status
    lda copy_source
    bne :+
    jmp no_source
:
    cmp #9
    bcc :+
    jmp no_source
:
    sec
    sbc #1
    sta copy_source_index
    tax
    lda geo_present,x
    bne :+
    jmp no_source
:
    bpl :+
    jmp bad_source_geometry
:

    lda copy_target
    beq no_target
    cmp #9
    bcs no_target
    sec
    sbc #1
    sta copy_target_index
    tax
    lda geo_present,x
    beq no_target

    ldx copy_source_index
    lda geo_total_lo,x
    sta copy_total_lo
    lda geo_total_hi,x
    sta copy_total_hi
    lda geo_bps_lo,x
    sta copy_bps_lo
    lda geo_bps_hi,x
    sta copy_bps_hi
    lda geo_tracks,x
    sta copy_tracks
    lda geo_sides,x
    sta copy_sides
    lda geo_spt_lo,x
    sta copy_spt_lo
    lda geo_spt_hi,x
    sta copy_spt_hi
    lda geo_density,x
    sta copy_density
    lda geo_percom_ok,x
    sta copy_percom_ok
    jsr calculate_required_banks
    jsr memory_build_bank_list
    lda mem_usable_banks
    beq no_memory
    lda #0
    sta copy_single_pass
    lda mem_buffer_units_hi
    cmp copy_required_units_hi
    bcc capacity_checked
    bne one_pass
    lda mem_buffer_units_lo
    cmp copy_required_units_lo
    bcc capacity_checked
one_pass:
    lda #1
    sta copy_single_pass
capacity_checked:
    jsr copy_begin_chunks
    clc
    rts

no_source:
    lda #COPY_NO_SOURCE
    bne fail
no_target:
    lda #COPY_NO_TARGET
    bne fail
no_memory:
    lda #COPY_NO_MEMORY
    bne fail
bad_source_geometry:
    lda #COPY_GEOMETRY
fail:
    sta copy_error_kind
    sec
    rts
.endproc

; Starts a sector-aligned sequence of buffer-sized passes. One 16K bank is
; enough to copy any supported geometry, although a one-drive copy then
; requires a disk swap between every chunk.
.proc copy_begin_chunks
    lda #1
    sta copy_chunk_start_lo
    sta copy_pass_number
    lda #0
    sta copy_chunk_start_hi
    jmp calculate_chunk_end
.endproc

; Advances to the next chunk. Carry set means the whole disk is complete.
.proc copy_advance_chunk
    lda copy_chunk_end_lo
    cmp copy_total_lo
    bne advance
    lda copy_chunk_end_hi
    cmp copy_total_hi
    beq finished
advance:
    lda copy_chunk_end_lo
    clc
    adc #1
    sta copy_chunk_start_lo
    lda copy_chunk_end_hi
    adc #0
    sta copy_chunk_start_hi
    inc copy_pass_number
    jsr calculate_chunk_end
    clc
    rts
finished:
    sec
    rts
.endproc

; Calculates the largest complete-sector range which fits in all currently
; usable 16K banks. Capacity and use are expressed in 128-byte units.
.proc calculate_chunk_end
    lda mem_buffer_units_lo
    sta copy_capacity_lo
    lda mem_buffer_units_hi
    sta copy_capacity_hi

    lda #0
    sta copy_used_lo
    sta copy_used_hi
    lda copy_chunk_start_lo
    sta copy_candidate_lo
    sta copy_chunk_end_lo
    lda copy_chunk_start_hi
    sta copy_candidate_hi
    sta copy_chunk_end_hi

candidate_loop:
    jsr get_candidate_units
    lda copy_used_lo
    clc
    adc copy_sector_units
    sta copy_units_lo
    lda copy_used_hi
    adc #0
    sta copy_units_hi
    lda copy_units_hi
    cmp copy_capacity_hi
    bcc accept
    bne full
    lda copy_units_lo
    cmp copy_capacity_lo
    bcc accept
    beq accept
full:
    rts

accept:
    lda copy_units_lo
    sta copy_used_lo
    lda copy_units_hi
    sta copy_used_hi
    lda copy_candidate_lo
    sta copy_chunk_end_lo
    lda copy_candidate_hi
    sta copy_chunk_end_hi

    lda copy_candidate_lo
    cmp copy_total_lo
    bne next_candidate
    lda copy_candidate_hi
    cmp copy_total_hi
    beq full
next_candidate:
    inc copy_candidate_lo
    bne candidate_loop
    inc copy_candidate_hi
    jmp candidate_loop
.endproc

.proc get_candidate_units
    lda copy_candidate_hi
    bne normal
    lda copy_candidate_lo
    cmp #4
    bcs normal
    lda #1
    sta copy_sector_units
    rts
normal:
    lda copy_bps_hi
    beq one
    cmp #1
    beq two
    lda #4
    bne save
two:
    lda #2
    bne save
one:
    lda #1
save:
    sta copy_sector_units
    rts
.endproc

; Configures and formats the target to match the source geometry snapshot.
; Carry clear on success. This is the only operation here which erases media.
.proc copy_format_target
    lda copy_percom_ok
    beq choose_format_command

    lda copy_tracks
    sta sio_percom_buf
    lda #0
    sta sio_percom_buf+1
    lda copy_spt_hi
    sta sio_percom_buf+2
    lda copy_spt_lo
    sta sio_percom_buf+3
    lda copy_sides
    sec
    sbc #1
    sta sio_percom_buf+4
    lda copy_density
    sta sio_percom_buf+5
    lda copy_bps_hi
    sta sio_percom_buf+6
    lda copy_bps_lo
    sta sio_percom_buf+7
    lda #1
    sta sio_percom_buf+8
    lda #0
    sta sio_percom_buf+9
    sta sio_percom_buf+10
    sta sio_percom_buf+11

    lda #3
    sta copy_retry
percom_retry:
    lda copy_target
    jsr sio_write_percom
    bcc choose_format_command
    dec copy_retry
    bne percom_retry
    lda #COPY_FORMAT_ERROR
    jmp remember_io_error

choose_format_command:
    lda #CMD_FORMAT
    sta sio_format_command
    lda copy_bps_hi
    bne set_length
    lda copy_bps_lo
    cmp #128
    bne set_length
    lda copy_spt_hi
    bne set_length
    lda copy_spt_lo
    cmp #26
    bne set_length
    lda #CMD_FORMAT_ED
    sta sio_format_command

set_length:
    lda copy_bps_lo
    sta sio_length_lo
    lda copy_bps_hi
    sta sio_length_hi
    lda #2
    sta copy_retry
format_retry:
    lda copy_target
    jsr sio_format_disk
    bcc formatted
    dec copy_retry
    bne format_retry
    lda #COPY_FORMAT_ERROR
    jmp remember_io_error
formatted:
    clc
    rts
.endproc

; Rechecks the target after the user has inserted or confirmed the destination
; disk. The source geometry snapshot from copy_prepare remains intact.
.proc copy_validate_target
    ldx copy_target_index
    lda geo_present,x
    beq no_target
    bmi bad_geometry
    lda geo_bps_lo,x
    cmp copy_bps_lo
    bne bad_geometry
    lda geo_bps_hi,x
    cmp copy_bps_hi
    bne bad_geometry
    lda geo_total_lo,x
    cmp copy_total_lo
    bne bad_geometry
    lda geo_total_hi,x
    cmp copy_total_hi
    bne bad_geometry
    clc
    rts
no_target:
    lda #COPY_NO_TARGET
    bne fail
bad_geometry:
    lda #COPY_GEOMETRY
fail:
    sta copy_error_kind
    sec
    rts
.endproc

; Rechecks the source after a disk swap in a single-drive, multi-pass copy.
.proc copy_validate_source
    ldx copy_source_index
    lda geo_present,x
    beq no_source
    bmi bad_geometry
    lda geo_bps_lo,x
    cmp copy_bps_lo
    bne bad_geometry
    lda geo_bps_hi,x
    cmp copy_bps_hi
    bne bad_geometry
    lda geo_total_lo,x
    cmp copy_total_lo
    bne bad_geometry
    lda geo_total_hi,x
    cmp copy_total_hi
    bne bad_geometry
    clc
    rts
no_source:
    lda #COPY_NO_SOURCE
    bne fail
bad_geometry:
    lda #COPY_GEOMETRY
fail:
    sta copy_error_kind
    sec
    rts
.endproc

; Reads the current source chunk into the available buffer.
.proc copy_read_all
    jsr begin_transfer
sector_loop:
    jsr set_sector_length
    lda #3
    sta copy_retry
retry:
    lda copy_source
    jsr sio_read_sector
    bcc read_ok
    dec copy_retry
    bne retry
    lda #COPY_READ_ERROR
    jmp remember_io_error
read_ok:
    lda #<sio_sector_buf
    ldy #>sio_sector_buf
    jsr buffer_store
    bcc stored
    lda #COPY_BUFFER_ERROR
    jmp remember_error
stored:
    jsr progress_and_next
    bcc sector_loop
    clc
    rts
.endproc

; Writes the current buffered chunk using verified-write $57.
.proc copy_write_all
    jsr begin_transfer
sector_loop:
    jsr set_sector_length
    lda #<sio_sector_buf
    ldy #>sio_sector_buf
    jsr buffer_load
    bcc loaded
    lda #COPY_BUFFER_ERROR
    jmp remember_error
loaded:
    lda #3
    sta copy_retry
retry:
    lda copy_target
    jsr sio_write_sector
    bcc written
    dec copy_retry
    bne retry
    lda #COPY_WRITE_ERROR
    jmp remember_io_error
written:
    jsr progress_and_next
    bcc sector_loop
    clc
    rts
.endproc

; Reads the current target chunk and compares it with the buffered source.
.proc copy_verify_all
    jsr begin_transfer
sector_loop:
    jsr set_sector_length
    lda #3
    sta copy_retry
retry:
    lda copy_target
    jsr sio_read_sector
    bcc read_ok
    dec copy_retry
    bne retry
    lda #COPY_VERIFY_IO
    jmp remember_io_error
read_ok:
    jsr buffer_compare
    bcc verified
    lda #COPY_VERIFY_DATA
    jmp remember_error
verified:
    jsr progress_and_next
    bcc sector_loop
    clc
    rts
.endproc

.proc begin_transfer
    lda #COPY_OK
    sta copy_error_kind
    lda copy_chunk_start_lo
    sta copy_current_lo
    lda copy_chunk_start_hi
    sta copy_current_hi
    jmp buffer_reset
.endproc

; Sets sector and length variables. Atari boot sectors 1-3 are always 128
; bytes, also on 256/512-byte media.
.proc set_sector_length
    lda copy_current_lo
    sta sio_sector_lo
    lda copy_current_hi
    sta sio_sector_hi
    bne normal_length
    lda copy_current_lo
    cmp #4
    bcs normal_length
    lda #128
    sta sio_length_lo
    lda #0
    sta sio_length_hi
    rts
normal_length:
    lda copy_bps_lo
    sta sio_length_lo
    lda copy_bps_hi
    sta sio_length_hi
    rts
.endproc

; Carry set when the last sector has just completed.
.proc progress_and_next
    jsr copy_ui_progress
    lda copy_current_lo
    cmp copy_chunk_end_lo
    bne increment
    lda copy_current_hi
    cmp copy_chunk_end_hi
    beq finished
increment:
    inc copy_current_lo
    bne more
    inc copy_current_hi
more:
    clc
    rts
finished:
    sec
    rts
.endproc

.proc calculate_required_banks
    lda copy_total_lo
    sta copy_units_lo
    lda copy_total_hi
    sta copy_units_hi
    lda copy_bps_hi
    beq units_ready
    cmp #1
    beq twice

    ; 512 byte sectors: units = total*4 - 9 because sectors 1-3 use 128.
    asl copy_units_lo
    rol copy_units_hi
    asl copy_units_lo
    rol copy_units_hi
    lda copy_units_lo
    sec
    sbc #9
    sta copy_units_lo
    lda copy_units_hi
    sbc #0
    sta copy_units_hi
    jmp units_ready

twice:
    ; 256 byte sectors: units = total*2 - 3.
    asl copy_units_lo
    rol copy_units_hi
    lda copy_units_lo
    sec
    sbc #3
    sta copy_units_lo
    lda copy_units_hi
    sbc #0
    sta copy_units_hi

units_ready:
    lda copy_units_lo
    sta copy_required_units_lo
    lda copy_units_hi
    sta copy_required_units_hi

    ; Required slots = ceil(128-byte units / 128).
    lda copy_units_lo
    clc
    adc #127
    sta copy_units_lo
    lda copy_units_hi
    adc #0
    sta copy_units_hi
    ldx #7
shift:
    lsr copy_units_hi
    ror copy_units_lo
    dex
    bne shift
    lda copy_units_lo
    sta copy_required_banks
    rts
.endproc

.proc remember_io_error
    pha
    lda sio_result
    sta copy_error_status
    pla
    ; fall through
.endproc

.proc remember_error
    sta copy_error_kind
    lda copy_current_lo
    sta copy_error_sector_lo
    lda copy_current_hi
    sta copy_error_sector_hi
    sec
    rts
.endproc
