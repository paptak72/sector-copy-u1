.include "os.inc"

; ---------------------------------------------------------------------------
; Diagnostyka rozpoznawania gestosci standardowego XF551
; ---------------------------------------------------------------------------
;
; Ten pomocniczy XEX wykonuje dokladnie te operacje, ktore rozstrzygaja
; zgloszony przypadek DD rozpoznanego jako ED. Zachowuje wynik i rzeczywista
; predkosc kazdego rozkazu, oba czterobajtowe STATUS-y oraz PERCOM. Ekran nie
; znika sam: klawisze 1..8 wybieraja stacje, S ponawia probe, a Q wykonuje
; zimny start. Kod korzysta z tego samego sterownika HSIO i tych samych
; procedur SIO co program glowny, wiec nie maskuje problemu systemowym SIOV.
;
; Oczekiwana sekwencja dla stockowego XF551 i fizycznego DD:
;
;   READ 1/128 -> STATUS 1 = $80 (przejsciowe ED)
;   READ 4/256 -> STATUS 2 = $60 (DD, dwie strony z punktu widzenia firmware)
;
; Na prawdziwym ED READ 4/256 celowo konczy sie timeoutem, poniewaz stacja
; wysyla 128 B. STATUS 2 pozostaje wtedy $80. Wynik READ 4 nie jest zatem
; klasyfikatorem; rozstrzyga zawsze drugi STATUS.

.import ui_init
.import ui_begin_screen
.import ui_get_key_upper
.import ui_set_cursor
.import ui_print_char
.import ui_print_z

.import sio_clear_speeds
.import sio_get_mode
.import sio_read_boot_sector
.import sio_probe_xf_dd
.import sio_status
.import sio_get_percom
.import sio_result
.import sio_actual_mode
.import sio_status_buf
.import sio_percom_buf

.segment "ZEROPAGE"
diag_hex_ptr:       .res 2

.segment "BSS"
diag_drive:         .res 1
diag_profile:       .res 1
diag_tick:          .res 1
diag_hex_count:     .res 1

; Kazda para zawiera status SIO rozkazu i predkosc, z ktora faktycznie sie
; zakonczyl. $FF przy READ 4 oznacza, ze sonda nie byla potrzebna.
diag_r1_result:     .res 1
diag_r1_mode:       .res 1
diag_st1_result:    .res 1
diag_st1_mode:      .res 1
diag_p4_result:     .res 1
diag_p4_mode:       .res 1
diag_st2_result:    .res 1
diag_st2_mode:      .res 1
diag_pc_result:     .res 1
diag_pc_mode:       .res 1

diag_status1:       .res 4
diag_status2:       .res 4
diag_percom:        .res 12

.segment "RODATA"
title:              .byte "DIAGNOSTYKA GESTOSCI XF551", 0
scanning:           .byte "BADANIE STACJI D", 0
drive_label:        .byte "STACJA: D", 0
profile_label:      .byte "  PROFIL:$", 0
read1_label:        .byte "READ 1/128   WYN:$", 0
status1_label:      .byte "STATUS 1     WYN:$", 0
probe4_label:       .byte "READ 4/256   WYN:$", 0
status2_label:      .byte "STATUS 2     WYN:$", 0
percom_label:       .byte "PERCOM       WYN:$", 0
mode_label:         .byte " SIO:$", 0
bytes_label:        .byte "BAJTY: ", 0
result_label:       .byte "WYNIK: ", 0
result_dd:          .byte "DD - 18 X 256 B", 0
result_ed:          .byte "ED - 26 X 128 B", 0
result_sd:          .byte "SD - 18 X 128 B", 0
result_error:       .byte "BRAK DRUGIEGO STATUS", 0
expected_label:     .byte "XF551/DD: OCZEKIWANE $80 -> $60", 0
skipped_label:      .byte "$FF = SONDA READ 4 POMINIETA", 0
keys_label:         .byte "1-8 STACJA   S PONOW   Q RESTART", 0

.segment "CODE"

.proc diag_start
    cld
    ; Wylacz BASIC/SELF TEST i pozostaw OS oraz glowny RAM. Diagnostyka nie
    ; potrzebuje ROM-u BASIC i musi widziec te same zasoby co pelny kopier.
    lda #$FF
    sta PORTB
    jsr ui_init
    lda #1
    sta diag_drive
    jmp run_probe
.endproc

; Ustaw caly bufor odpowiedzi na $EE. Przy bledzie transmisji ekran pokazuje
; wtedy, ktore bajty rzeczywiscie nie zostaly odebrane, zamiast starego STATUS.
.proc poison_status
    ldx #3
    lda #$EE
loop:
    sta sio_status_buf,x
    dex
    bpl loop
    rts
.endproc

.proc poison_percom
    ldx #11
    lda #$EE
loop:
    sta sio_percom_buf,x
    dex
    bpl loop
    rts
.endproc

.proc snapshot_status1
    ldx #3
loop:
    lda sio_status_buf,x
    sta diag_status1,x
    dex
    bpl loop
    rts
.endproc

.proc snapshot_status2
    ldx #3
loop:
    lda sio_status_buf,x
    sta diag_status2,x
    dex
    bpl loop
    rts
.endproc

.proc snapshot_percom
    ldx #11
loop:
    lda sio_percom_buf,x
    sta diag_percom,x
    dex
    bpl loop
    rts
.endproc

.proc wait_nine_frames
    lda RTCLOK+2
    sta diag_tick
loop:
    lda RTCLOK+2
    sec
    sbc diag_tick
    cmp #9
    bcc loop
    rts
.endproc

.proc run_probe
    jsr ui_begin_screen
    lda #2
    ldx #10
    jsr ui_set_cursor
    lda #<scanning
    ldy #>scanning
    jsr ui_print_z
    lda diag_drive
    jsr print_decimal_digit

    ; Kazde ponowienie zaczyna negocjacje profilu od zera. Dzieki temu ekran
    ; nie odziedziczy trybu stacji po poprzednim numerze ani nie ominie testu.
    jsr sio_clear_speeds

    lda diag_drive
    jsr sio_read_boot_sector
    lda sio_result
    sta diag_r1_result
    lda sio_actual_mode
    sta diag_r1_mode

    jsr poison_status
    lda diag_drive
    jsr sio_status
    lda sio_result
    sta diag_st1_result
    lda sio_actual_mode
    sta diag_st1_mode
    jsr snapshot_status1

    lda diag_drive
    jsr sio_get_mode
    bcc profile_known
    lda #$FF
profile_known:
    sta diag_profile

    ; Tak jak program glowny, diagnostyka sonduje kazda pewnie rozpoznana
    ; rodzine XF. Nie ufa tu pierwszym bitom gestosci, bo po bledzie READ 1
    ; moga nadal opisywac poprzedni nosnik. Sygnatura timeoutu $FE pochodzi ze
    ; stockowego STATUS; profil $40 niezaleznie potwierdza XF551 High Speed.
    lda #$FF
    sta diag_p4_result
    sta diag_p4_mode
    lda diag_st1_result
    cmp #SIO_OK
    bne copy_first_status
    lda diag_status1+2
    cmp #$FE
    beq do_probe4
    lda diag_profile
    cmp #$40
    bne copy_first_status

do_probe4:
    lda diag_drive
    jsr sio_probe_xf_dd
    lda sio_result
    sta diag_p4_result
    lda sio_actual_mode
    sta diag_p4_mode
    jsr wait_nine_frames

    jsr poison_status
    lda diag_drive
    jsr sio_status
    lda sio_result
    sta diag_st2_result
    lda sio_actual_mode
    sta diag_st2_mode
    jsr snapshot_status2
    jmp get_percom

copy_first_status:
    lda diag_st1_result
    sta diag_st2_result
    lda diag_st1_mode
    sta diag_st2_mode
    ldx #3
copy_loop:
    lda diag_status1,x
    sta diag_status2,x
    dex
    bpl copy_loop

get_percom:
    jsr poison_percom
    lda diag_drive
    jsr sio_get_percom
    lda sio_result
    sta diag_pc_result
    lda sio_actual_mode
    sta diag_pc_mode
    jsr snapshot_percom

    jsr draw_results

wait_key:
    jsr ui_get_key_upper
    cmp #'1'
    bcc not_drive
    cmp #'9'
    bcs not_drive
    sec
    sbc #'0'
    sta diag_drive
    jmp run_probe
not_drive:
    cmp #'S'
    beq rerun
    cmp #'Q'
    beq restart
    cmp #ATASCII_ESC
    beq restart
    jmp wait_key
rerun:
    jmp run_probe
restart:
    jmp COLDSV
.endproc

; A/Y wskazuje pare wynik/predkosc.
.proc print_result_mode
    sta diag_hex_ptr
    sty diag_hex_ptr+1
    ldy #0
    lda (diag_hex_ptr),y
    jsr print_hex
    lda #<mode_label
    ldy #>mode_label
    jsr ui_print_z
    ldy #1
    lda (diag_hex_ptr),y
    jmp print_hex
.endproc

; A/Y wskazuje blok, X zawiera liczbe bajtow. Kazdy bajt jest poprzedzony '$'.
.proc print_hex_block
    sta diag_hex_ptr
    sty diag_hex_ptr+1
    stx diag_hex_count
next:
    lda #'$'
    jsr ui_print_char
    ldy #0
    lda (diag_hex_ptr),y
    jsr print_hex
    lda #' '
    jsr ui_print_char
    inc diag_hex_ptr
    bne :+
    inc diag_hex_ptr+1
:
    dec diag_hex_count
    bne next
    rts
.endproc

.proc print_hex
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr print_nibble
    pla
    and #$0F
    ; Przejscie bezposrednio do drugiej cyfry.
.endproc

.proc print_nibble
    cmp #10
    bcc digit
    clc
    adc #'A'-10
    jmp ui_print_char
digit:
    ora #'0'
    jmp ui_print_char
.endproc

.proc print_decimal_digit
    ora #'0'
    jmp ui_print_char
.endproc

.proc draw_results
    jsr ui_begin_screen

    lda #1
    ldx #6
    jsr ui_set_cursor
    lda #<title
    ldy #>title
    jsr ui_print_z

    lda #2
    ldx #2
    jsr ui_set_cursor
    lda #<drive_label
    ldy #>drive_label
    jsr ui_print_z
    lda diag_drive
    jsr print_decimal_digit
    lda #<profile_label
    ldy #>profile_label
    jsr ui_print_z
    lda diag_profile
    jsr print_hex

    lda #4
    ldx #2
    jsr ui_set_cursor
    lda #<read1_label
    ldy #>read1_label
    jsr ui_print_z
    lda #<diag_r1_result
    ldy #>diag_r1_result
    jsr print_result_mode

    lda #5
    ldx #2
    jsr ui_set_cursor
    lda #<status1_label
    ldy #>status1_label
    jsr ui_print_z
    lda #<diag_st1_result
    ldy #>diag_st1_result
    jsr print_result_mode
    lda #6
    ldx #2
    jsr ui_set_cursor
    lda #<bytes_label
    ldy #>bytes_label
    jsr ui_print_z
    lda #<diag_status1
    ldy #>diag_status1
    ldx #4
    jsr print_hex_block

    lda #8
    ldx #2
    jsr ui_set_cursor
    lda #<probe4_label
    ldy #>probe4_label
    jsr ui_print_z
    lda #<diag_p4_result
    ldy #>diag_p4_result
    jsr print_result_mode

    lda #9
    ldx #2
    jsr ui_set_cursor
    lda #<status2_label
    ldy #>status2_label
    jsr ui_print_z
    lda #<diag_st2_result
    ldy #>diag_st2_result
    jsr print_result_mode
    lda #10
    ldx #2
    jsr ui_set_cursor
    lda #<bytes_label
    ldy #>bytes_label
    jsr ui_print_z
    lda #<diag_status2
    ldy #>diag_status2
    ldx #4
    jsr print_hex_block

    lda #12
    ldx #2
    jsr ui_set_cursor
    lda #<percom_label
    ldy #>percom_label
    jsr ui_print_z
    lda #<diag_pc_result
    ldy #>diag_pc_result
    jsr print_result_mode
    lda #13
    ldx #2
    jsr ui_set_cursor
    lda #<diag_percom
    ldy #>diag_percom
    ldx #6
    jsr print_hex_block
    lda #14
    ldx #2
    jsr ui_set_cursor
    lda #<(diag_percom+6)
    ldy #>(diag_percom+6)
    ldx #6
    jsr print_hex_block

    lda #16
    ldx #2
    jsr ui_set_cursor
    lda #<result_label
    ldy #>result_label
    jsr ui_print_z
    lda diag_st2_result
    cmp #SIO_OK
    bne show_error
    lda diag_status2
    and #$20
    bne show_dd
    lda diag_status2
    bmi show_ed
    lda #<result_sd
    ldy #>result_sd
    bne show_result
show_ed:
    lda #<result_ed
    ldy #>result_ed
    bne show_result
show_dd:
    lda #<result_dd
    ldy #>result_dd
    bne show_result
show_error:
    lda #<result_error
    ldy #>result_error
show_result:
    jsr ui_print_z

    lda #18
    ldx #2
    jsr ui_set_cursor
    lda #<expected_label
    ldy #>expected_label
    jsr ui_print_z
    lda #19
    ldx #2
    jsr ui_set_cursor
    lda #<skipped_label
    ldy #>skipped_label
    jsr ui_print_z
    lda #21
    ldx #2
    jsr ui_set_cursor
    lda #<keys_label
    ldy #>keys_label
    jmp ui_print_z
.endproc

.segment "RUNAD"
    .word diag_start
