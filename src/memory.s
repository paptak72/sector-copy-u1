.include "os.inc"

; ---------------------------------------------------------------------------
; Wykrywanie i obsluga pamieci podstawowej/rozszerzonej
; ---------------------------------------------------------------------------
;
; Rozszerzenia zgodne z 130XE pokazuja wybrany bank w oknie $4000-$7FFF przez
; bity PORTB. Rozne modernizacje dekoduja rozne zestawy bitow, dlatego program
; nie zaklada nazwy standardu z samego modelu komputera. W trybie pelnym bada
; kombinacje selektora, zapisuje sygnatury w oknie, odrzuca aliasy tego samego
; banku i buduje mem_bank_indices z fizycznie roznych 16-kilobajtowych okien.
;
; Ultimate 1MB udostepnia dodatkowo pamiec glowna pod tym samym oknem; po
; bezpiecznym odlaczeniu DOS-u moze ona zostac ostatnia pozycja bufora. Kazde
; mapowanie jest krotkie: buffer.s przywraca MAIN_PORTB przed powrotem do kodu,
; systemu lub ekranu.
;
; Tryb zachowania DOS-u celowo NIE sonduje bankow. Nie znamy wtedy wlasnosci
; RAM-dysku ani rezydentnych sterownikow, wiec uzywane jest tylko wolne glowne
; $4000-$7FFF, a PORTB, APPMHI, marginesy, kolory i $80-$8F sa odtwarzane przed
; RTS do programu wywolujacego.

.export memory_takeover
.export memory_keep_dos
.export memory_detect_launch
.export memory_save_environment
.export memory_reserve_application
.export memory_restore_environment
.export memory_probe
.export memory_build_bank_list
.export memory_select_bank
.export memory_restore_bank
.export mem_sdx
.export mem_dos_present
.export mem_keep_dos
.export mem_free_banks
.export mem_total_banks
.export mem_usable_banks
.export mem_bank_indices
.export mem_pbmask
.export mem_main_free_lo
.export mem_main_free_hi
.export mem_buffer_units_lo
.export mem_buffer_units_hi

MAX_EXT_BANKS = 64
MAIN_PORTB    = $FF
APP_ZP_BYTES  = 16

.segment "ZEROPAGE"
clear_ptr:          .res 2

.segment "BSS"
mem_sdx:            .res 1
mem_dos_present:    .res 1
mem_keep_dos:       .res 1
mem_free_banks:     .res 1
mem_total_banks:    .res 1
mem_usable_banks:   .res 1
mem_pbmask:         .res 1
mem_main_free_lo:   .res 1
mem_main_free_hi:   .res 1
mem_buffer_units_lo:.res 1
mem_buffer_units_hi:.res 1
mem_bank_indices:   .res 65
probe_index:        .res 1
probe_raw_port:     .res 1
probe_main_alias:   .res 1
probe_first_port:   .res 1
probe_have_first:   .res 1
saved_portb:        .res 1
saved_appmhi_lo:    .res 1
saved_appmhi_hi:    .res 1
saved_lmargn:       .res 1
saved_rmargn:       .res 1
saved_color1:       .res 1
saved_color2:       .res 1
saved_color4:       .res 1
saved_crsinh:       .res 1
saved_app_zp:       .res APP_ZP_BYTES

.segment "CODE"

.import __RODATA_RUN__
.import __RODATA_SIZE__

; Preserve the transient application's zero-page workspace before the copier
; uses it. This makes a later RTS to a retained DOS possible.
.proc memory_save_environment
    lda PORTB
    sta saved_portb
    lda APPMHI
    sta saved_appmhi_lo
    lda APPMHI+1
    sta saved_appmhi_hi
    lda LMARGN
    sta saved_lmargn
    lda RMARGN
    sta saved_rmargn
    lda COLOR1
    sta saved_color1
    lda COLOR2
    sta saved_color2
    lda COLOR4
    sta saved_color4
    lda CRSINH
    sta saved_crsinh
    ldx #0
save_zp:
    lda $80,x
    sta saved_app_zp,x
    inx
    cpx #APP_ZP_BYTES
    bcc save_zp
    rts
.endproc

; Tell E:/S: that screen and display-list memory must stay above the entire
; resident application. Without APPMHI, reopening E: may place GR.0 screen
; RAM on top of the program's code and read-only data.
.proc memory_reserve_application
    lda #<(__RODATA_RUN__ + __RODATA_SIZE__)
    sta APPMHI
    lda #>(__RODATA_RUN__ + __RODATA_SIZE__)
    sta APPMHI+1
    rts
.endproc

; Detect a resident DOS without calling any DOS-specific entry point.
; SDX has a stable signature at $0700. For other DOSes, a DOSVEC pointing
; into RAM is treated as evidence that a resident environment launched us.
.proc memory_detect_launch
    lda #0
    sta mem_sdx
    sta mem_dos_present
    sta mem_keep_dos
    lda $0700
    cmp #'S'
    bne check_dosvec
    lda #1
    sta mem_sdx
    sta mem_dos_present
    rts

check_dosvec:
    lda DOSVEC
    cmp #<COLDSV
    bne possible_ram_vector
    lda DOSVEC+1
    cmp #>COLDSV
    beq no_dos
possible_ram_vector:
    lda DOSVEC+1
    beq no_dos
    cmp #$C0
    bcs no_dos
    lda #1
    sta mem_dos_present
no_dos:
    rts
.endproc

; Keep the resident DOS intact. No destructive bank probing is allowed in
; this mode because an arbitrary DOS or RAMdisk may own extended-memory banks.
.proc memory_keep_dos
    lda MEMLO+1
    cmp #$36
    bcc safe
    bne unavailable
    lda MEMLO
    cmp #$01
    bcs unavailable
safe:
    lda #1
    sta mem_keep_dos
    jmp memory_build_bank_list
unavailable:
    sec
    rts
.endproc

; Restore the state used by the launching DOS. The caller must execute RTS
; immediately afterwards, while the original invocation stack is still live.
.proc memory_restore_environment
    lda saved_portb
    sta PORTB
    lda saved_appmhi_lo
    sta APPMHI
    lda saved_appmhi_hi
    sta APPMHI+1
    lda saved_lmargn
    sta LMARGN
    lda saved_rmargn
    sta RMARGN
    lda saved_color1
    sta COLOR1
    lda saved_color2
    sta COLOR2
    lda saved_color4
    sta COLOR4
    lda saved_crsinh
    sta CRSINH
    ldx #0
restore_zp:
    lda saved_app_zp,x
    sta $80,x
    inx
    cpx #APP_ZP_BYTES
    bcc restore_zp
    rts
.endproc

; Called after the user has explicitly selected full-memory mode. From this
; point the application deliberately does not return to the loader or DOS.
.proc memory_takeover
    lda #0
    sta mem_keep_dos
    ; Establish a safe main-memory state before changing selector bits.
    ; This is also required by the U1MB 576K/1088K PORTB shadow logic.
    lda #MAIN_PORTB
    sta PORTB

    ; XEX loaders and DOSes often leave deferred VBI hooks and software
    ; timers in their resident area. Remove those hooks before reclaiming it.
    sei
    lda #<SYSVBV
    sta VVBLKI
    lda #>SYSVBV
    sta VVBLKI+1
    lda #<XITVBV
    sta VVBLKD
    lda #>XITVBV
    sta VVBLKD+1
    lda #0
    ldx #9
clear_timers:
    sta CDTMV1,x
    dex
    bpl clear_timers
    cli

    ; Do not let an abandoned PBI/DOS handler intercept later serial calls.
    lda #0
    sta PDVMSK
    sta SHPDVS
    sta PDMSK

    ; A warm-start through an overwritten DOS is unsafe. Redirect DOSVEC to
    ; the OS cold-start vector and then reclaim the resident DOS area.
    lda #<COLDSV
    sta DOSVEC
    lda #>COLDSV
    sta DOSVEC+1

    lda #0
    sta clear_ptr
    lda #$07
    sta clear_ptr+1
    ldy #0
clear_dos:
    lda #0
    sta (clear_ptr),y
    iny
    bne clear_dos
    inc clear_ptr+1
    lda clear_ptr+1
    ; Nie wolno czyscic stron $36-$37. Pod $3600 zaczyna sie segment AUXCODE
    ; z tekstami menu oraz procedurami paskow postepu. Dawna granica $38
    ; zerowala ten kod po zaladowaniu XEX-a; kopiowanie dochodzilo wtedy do
    ; zielonego ekranu i zawieszalo sie przed pierwsza komenda READ. Bajty
    ; Obie strony nie naleza do bufora i pozostaja nietkniete.
    cmp #$36
    bcc clear_dos

    ; The copier owns conventional memory from $0700 upward. The banked
    ; buffer deliberately uses the contiguous $4000-$7FFF main window.
    lda #<$0700
    sta MEMLO
    lda #>$0700
    sta MEMLO+1
    jmp memory_build_bank_list
.endproc

; Compatibility entry point used by the UI.
.proc memory_probe
    jmp memory_build_bank_list
.endproc

; Probe every possible 1088K RAMBO PORTB selector. A two-pass signature test
; naturally collapses aliases on 64K, 130XE, 320K and 576K machines:
; only the last selector which reaches a physical bank retains its signature.
.proc memory_build_bank_list
    lda mem_keep_dos
    beq destructive_probe
    jmp memory_build_dos_safe

destructive_probe:
    lda #MAIN_PORTB
    sta PORTB

    lda #0
    sta mem_pbmask
    sta probe_have_first
    sta mem_main_free_lo
    lda #$40
    sta mem_main_free_hi

    ; Main $4000-$7FFF window is always the first 16K buffer bank.
    lda #MAIN_PORTB
    sta mem_bank_indices
    lda #1
    sta mem_usable_banks

    ; Write a unique four-byte signature through all 64 selector patterns.
    lda #0
    sta probe_index
write_loop:
    jsr probe_make_port
    sta PORTB
    ldx probe_index
    txa
    sta $4000
    eor #$FF
    sta $4001
    txa
    eor #$A5
    sta $4002
    txa
    eor #$5A
    sta $4003
    inc probe_index
    lda probe_index
    cmp #MAX_EXT_BANKS
    bcc write_loop

    ; If an expansion aliases one selector against main RAM, remember it so
    ; that the main window is not counted twice.
    lda #MAIN_PORTB
    sta PORTB
    jsr probe_read_signature
    bcs no_main_alias
    lda $4000
    sta probe_main_alias
    jmp scan_banks
no_main_alias:
    lda #$FF
    sta probe_main_alias

scan_banks:
    lda #0
    sta probe_index
read_loop:
    jsr probe_make_port
    sta probe_raw_port
    sta PORTB
    jsr probe_read_signature
    bcs next_selector
    lda $4000
    cmp probe_index
    bne next_selector
    cmp probe_main_alias
    beq next_selector

    ldy mem_usable_banks
    lda probe_raw_port
    sta mem_bank_indices,y
    iny
    sty mem_usable_banks

    ; Derive the selector-bit mask for display and diagnostics.
    lda probe_have_first
    bne compare_selector
    lda probe_raw_port
    sta probe_first_port
    lda #1
    sta probe_have_first
    bne next_selector
compare_selector:
    lda probe_raw_port
    eor probe_first_port
    ora mem_pbmask
    sta mem_pbmask

next_selector:
    inc probe_index
    lda probe_index
    cmp #MAX_EXT_BANKS
    bcc read_loop

    lda #MAIN_PORTB
    sta PORTB
    lda mem_usable_banks
    sta mem_total_banks
    sec
    sbc #1
    sta mem_free_banks
    jmp calculate_buffer_units
.endproc

; Conservative buffer map used while DOS stays resident. The program image
; starts at $8000, so $4000-$7FFF is a safe transient-program window only
; when MEMLO does not reach into it. Extended RAM is never touched here.
.proc memory_build_dos_safe
    lda #MAIN_PORTB
    sta PORTB
    lda #0
    sta mem_pbmask
    sta mem_free_banks
    sta mem_total_banks
    sta mem_usable_banks
    sta mem_main_free_lo
    sta mem_main_free_hi
    sta mem_buffer_units_lo
    sta mem_buffer_units_hi

    lda MEMLO+1
    cmp #$38
    bcc main_window_free
    bne no_window
    lda MEMLO
    bne no_window

main_window_free:
    lda #MAIN_PORTB
    sta mem_bank_indices
    lda #1
    sta mem_total_banks
    sta mem_usable_banks
    lda #$40
    sta mem_main_free_hi
no_window:
    lda mem_usable_banks
    beq no_capacity
    jmp calculate_buffer_units
no_capacity:
    clc
    rts
.endproc

; Total 128-byte units available to the streaming buffer.
.proc calculate_buffer_units
    lda mem_usable_banks
    and #1
    lsr
    ror
    sta mem_buffer_units_lo
    lda mem_usable_banks
    lsr
    sta mem_buffer_units_hi
    clc
    rts
.endproc

; Convert probe_index bits 0..5 into PORTB bits 1,2,3,5,6,7.
; Bit 4 remains clear (CPU window enabled), bit 0 remains set (OS ROM on).
.proc probe_make_port
    lda probe_index
    and #$07
    asl
    sta probe_raw_port
    lda probe_index
    and #$38
    asl
    asl
    ora probe_raw_port
    ora #$01
    rts
.endproc

; Carry clear when $4000-$4003 form a valid probe signature.
.proc probe_read_signature
    lda $4000
    eor #$FF
    cmp $4001
    bne invalid
    lda $4000
    eor #$A5
    cmp $4002
    bne invalid
    lda $4000
    eor #$5A
    cmp $4003
    bne invalid
    clc
    rts
invalid:
    sec
    rts
.endproc

; A = zero-based slot in mem_bank_indices.
.proc memory_select_bank
    cmp mem_usable_banks
    bcs unavailable
    tax
    lda mem_bank_indices,x
    sta PORTB
    clc
    rts
unavailable:
    sec
    rts
.endproc

.proc memory_restore_bank
    lda #MAIN_PORTB
    sta PORTB
    rts
.endproc
