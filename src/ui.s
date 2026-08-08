.include "os.inc"

; ---------------------------------------------------------------------------
; Interfejs tekstowy oparty na standardowych procedurach obslugi E: i K:
; ---------------------------------------------------------------------------
;
; E: tworzy ekran GRAPHICS 0 i sluzy tylko do wyjscia. Klawiatura jest otwarta
; osobno jako K: na IOCB #1, dlatego pojedynczy klawisz wraca natychmiast i nie
; wymaga RETURN. Rozdzielenie kanalow zapobiega pozostawaniu znaku konca linii
; w buforze po wyborze opcji.
;
; ui_begin_screen ustawia 40-kolumnowy obszar z marginesami 1..38. Kolumny 0
; i 39 sa zarezerwowane dla ramki semigraficznej. Pion korzysta z systemowego
; glifu $7C, ktory ma kreske dokladnie posrodku komorki w ROM-ach XL/XE.
;
; Teksty zrodlowe sa w ATASCII. Wizualizacja sektorow w main.s zapisuje jednak
; kody ekranowe bezposrednio pod SAVMSC, aby nie wykonywac setek wywolan CIO na
; kazdy sektor. Palety odczytu, zapisu i menu zmieniaja tylko rejestry COLOR*,
; wiec przejscie zielony->czerwony nie niszczy zawartosci ekranu.

.export ui_clear
.export ui_begin_screen
.export ui_init
.export ui_get_key
.export ui_get_key_upper
.export ui_wait_start_select
.export ui_wait_key
.export ui_delay_notice
.export ui_colors_menu
.export ui_colors_read
.export ui_colors_write
.export ui_colors_verify
.export ui_set_cursor
.export ui_print_char
.export ui_print_eol
.export ui_print_z
.export ui_print_u8
.export ui_print_u16
.exportzp ui_ptr

.segment "ZEROPAGE"
ui_ptr:          .res 2

.segment "BSS"
ui_num_lo:       .res 1
ui_num_hi:       .res 1
ui_digit:        .res 1
ui_started:      .res 1
ui_table_index:  .res 1
ui_tick_start:   .res 1

.segment "RODATA"
decimal_divisors:
    .word 10000, 1000, 100, 10, 1
editor_name:
    .byte "E:", 0
keyboard_name:
    .byte "K:", 0

.segment "CODE"

BOX_TL = $51
BOX_TR = $45
BOX_BL = $5A
BOX_BR = $43
BOX_H  = $52
; $7C = osiem wierszy po $18: pelna pionowa kreska posrodku glifu. Jej polozenie
; jest zgodne z pionowymi fragmentami glifow uzytych dla naroznikow ramki.
BOX_V  = $7C

; GR.0 pobiera odcien i jasnosc tla z COLOR2, a jasnosc tekstu z dolnego
; polbajtu COLOR1. Ustawienia daja granatowe tlo, jasnoniebieskie litery oraz
; ciemniejsza ramke na maszynach PAL i NTSC.
UI_TEXT_LUMA  = $0E
UI_BACKGROUND = $82
UI_BORDER     = $80
READ_BACKGROUND  = $C2
READ_BORDER      = $C0
WRITE_BACKGROUND = $32
WRITE_BORDER     = $30
VERIFY_BACKGROUND = $12
VERIFY_BORDER     = $10

.proc ui_init
    ldx #0
    lda #CIO_CLOSE
    sta ICCOM
    jsr CIOV

    lda #CIO_OPEN
    sta ICCOM
    lda #<editor_name
    sta ICBAL
    lda #>editor_name
    sta ICBAH
    lda #12
    sta ICAX1
    lda #0
    sta ICAX2
    ldx #0
    jsr CIOV
    lda #1
    sta LMARGN
    sta CRSINH
    lda #38
    sta RMARGN
    jsr ui_colors_menu
    jsr ui_init_keyboard
    rts
.endproc

; Palety GR.0 rozrozniaja etapy operacji: nawigacja jest niebieska, odczyt
; zielony, a destrukcyjne formatowanie i zapis czerwone.
.proc ui_colors_menu
    lda #UI_BACKGROUND
    ldx #UI_BORDER
    jmp ui_apply_colors
.endproc

.proc ui_colors_read
    lda #READ_BACKGROUND
    ldx #READ_BORDER
    jmp ui_apply_colors
.endproc

.proc ui_colors_write
    lda #WRITE_BACKGROUND
    ldx #WRITE_BORDER
    jmp ui_apply_colors
.endproc

; Weryfikacja jest osobnym etapem, a nie zwyklym odczytem. Zloto-zolta paleta
; odroznia ja natychmiast od zielonego zrodla i czerwonego zapisu, nie zmieniajac
; jasnosci tekstu ani ukladu ekranu.
.proc ui_colors_verify
    lda #VERIFY_BACKGROUND
    ldx #VERIFY_BORDER
    ; Przejscie bezposrednio do ui_set_stage_palette.
.endproc

.proc ui_apply_colors
    sta COLOR2
    stx COLOR4
    lda #UI_TEXT_LUMA
    sta COLOR1
    rts
.endproc

.proc ui_print_char
    pha
    lda #CIO_PUTCHR
    sta ICCOM
    lda #0
    sta ICBLL
    sta ICBLH
    pla
    ldx #0
    jmp CIOV
.endproc

.proc ui_clear
    lda #ATASCII_CLEAR
    jmp ui_print_char
.endproc

; Czysci ekran 40-kolumnowy i rysuje ramke semigraficzna Atari. Kolumny 0/39
; oraz wiersze 0/23 tworza obramowanie, a tekst zajmuje kolumny 1..38.
.proc ui_begin_screen
    jsr ui_colors_menu
    jsr ui_clear
    ; Pozwol E: przesunac jego kursor i zapamietany adres ekranu pod gorna
    ; ramke przed bezposrednim zapisem. Sama zmiana ROWCRS/COLCRS pozostawia
    ; OLDADR w ramce, wiec nastepne wywolanie CIO usuneloby jej fragment.
    jsr ui_print_eol
    lda SAVMSC
    sta ui_ptr
    clc
    adc #41
    sta OLDADR
    lda SAVMSC+1
    sta ui_ptr+1
    adc #0
    sta OLDADR+1

    ldy #0
    lda #BOX_TL
    sta (ui_ptr),y
    iny
    lda #BOX_H
top_line:
    sta (ui_ptr),y
    iny
    cpy #39
    bcc top_line
    lda #BOX_TR
    sta (ui_ptr),y

    ldx #22
side_rows:
    lda ui_ptr
    clc
    adc #40
    sta ui_ptr
    bcc :+
    inc ui_ptr+1
:
    ldy #0
    lda #BOX_V
    sta (ui_ptr),y
    ldy #39
    sta (ui_ptr),y
    dex
    bne side_rows

    lda ui_ptr
    clc
    adc #40
    sta ui_ptr
    bcc :+
    inc ui_ptr+1
:
    ldy #0
    lda #BOX_BL
    sta (ui_ptr),y
    iny
    lda #BOX_H
bottom_line:
    sta (ui_ptr),y
    iny
    cpy #39
    bcc bottom_line
    lda #BOX_BR
    sta (ui_ptr),y

    rts
.endproc

; Wejscie: A = wiersz, X = kolumna.
.proc ui_set_cursor
    sta ROWCRS
    stx COLCRS
    lda #0
    sta COLCRS+1
    rts
.endproc

.proc ui_print_eol
    lda #ATASCII_EOL
    jmp ui_print_char
.endproc

; Wejscie: A/Y = mlodszy/starszy bajt adresu lancucha ATASCII zakonczonego 0.
.proc ui_print_z
    sta ui_ptr
    sty ui_ptr+1
    ldy #0
loop:
    ldy #0
    lda (ui_ptr),y
    beq done
    jsr ui_print_char
    inc ui_ptr
    bne loop
    inc ui_ptr+1
    bne loop
done:
    rts
.endproc

; Wyswietla nieujemna wartosc A w zapisie dziesietnym.
.proc ui_print_u8
    ldy #0
    jmp ui_print_u16
.endproc

; Wyswietla nieujemna wartosc 16-bitowa A/Y (mlodszy/starszy) dziesietnie.
.proc ui_print_u16
    sta ui_num_lo
    sty ui_num_hi
    lda #0
    sta ui_started
    sta ui_table_index

next_divisor:
    lda #0
    sta ui_digit
subtract_loop:
    ldx ui_table_index
    lda ui_num_hi
    cmp decimal_divisors+1,x
    bcc digit_ready
    bne subtract
    lda ui_num_lo
    cmp decimal_divisors,x
    bcc digit_ready
subtract:
    lda ui_num_lo
    sec
    sbc decimal_divisors,x
    sta ui_num_lo
    lda ui_num_hi
    sbc decimal_divisors+1,x
    sta ui_num_hi
    inc ui_digit
    bne subtract_loop

digit_ready:
    lda ui_digit
    bne print_digit
    lda ui_started
    bne print_digit
    lda ui_table_index
    cmp #8
    beq print_digit
    jmp advance

print_digit:
    lda #1
    sta ui_started
    lda ui_digit
    ora #'0'
    jsr ui_print_char

advance:
    lda ui_table_index
    clc
    adc #2
    sta ui_table_index
    cmp #10
    bcc next_divisor
    rts
.endproc

; Rzadko wykonywany kod inicjalizacji lezy ponizej bufora sektorowego, dzieki
; czemu nie powieksza ciasnego obszaru aplikacji od $8000.
.segment "UICODE"

; E: buforuje caly wiersz i czeka na RETURN. Osobna procedura K: zwraca kazdy
; klawisz natychmiast, czego wymaga interaktywne menu. IOCB #1 dla K: jest
; niezalezny od wyjscia E: w IOCB #0.
.proc ui_init_keyboard
    ldx #$10
    lda #CIO_CLOSE
    sta ICCOM,x
    jsr CIOV

    lda #CIO_OPEN
    sta ICCOM,x
    lda #<keyboard_name
    sta ICBAL,x
    lda #>keyboard_name
    sta ICBAH,x
    lda #4
    sta ICAX1,x
    lda #0
    sta ICAX2,x
    jmp CIOV
.endproc

.proc ui_get_key
    ldx #$10
    lda #CIO_GETCHR
    sta ICCOM,x
    lda #0
    sta ICBLL,x
    sta ICBLH,x
    jsr CIOV
    rts
.endproc

; Interaktywne pomocniki sa w obszarze glownego kodu. UICODE pod $3D0A jest
; ograniczony do bajtu przed buforem $3E00 i zawiera tylko rzadka inicjalizacje
; CIO.
.segment "CODE"

; Wersja dla menu: K: zwraca natychmiast pojedynczy znak, a male litery sa
; skladane do wielkich. Centralna normalizacja usuwa z glownej petli pary
; porownan dla A/a, B/b itd. Znaki spoza alfabetu (cyfry, ESC) sa nietkniete.
.proc ui_get_key_upper
    jsr ui_get_key
    cmp #'a'
    bcc unchanged
    cmp #'z'+1
    bcs unchanged
    and #$DF
unchanged:
    rts
.endproc

; Czekaj na fizyczny START albo SELECT. Rejestr CONSOL ma logike aktywna zerem
; i nie jest czescia K:, dlatego nie mozna tu uzyc ui_get_key. Najpierw wymagamy
; zwolnienia obu klawiszy, aby START przytrzymany na poprzednim ekranie nie
; zatwierdzil automatycznie nastepnego. OPTION i kombinacje sa ignorowane.
;
; Wyjscie: C=1 START (kontynuuj), C=0 SELECT (anuluj/powrot).
.proc ui_wait_start_select
wait_initial_release:
    lda CONSOL
    and #$07
    cmp #$07
    bne wait_initial_release
wait_press:
    lda CONSOL
    and #$07
    cmp #$06                    ; tylko START: 111 -> 110
    beq start_pressed
    cmp #$05                    ; tylko SELECT: 111 -> 101
    bne wait_press
    ldx #0
    beq wait_release
start_pressed:
    ldx #1
wait_release:
    lda CONSOL
    and #$07
    cmp #$07
    bne wait_release
    cpx #1
    beq accepted
    clc
    rts
accepted:
    sec
    rts
.endproc

.segment "UICODE"

; Utrzymuj komunikat co najmniej przez jedna sekunde PAL (nieco krocej w NTSC).
; Odejmowanie zapewnia poprawny pomiar po zawinieciu mlodszego bajtu RTCLOK.
.proc ui_delay_notice
    lda RTCLOK+2
    sta ui_tick_start
wait_tick:
    lda RTCLOK+2
    sec
    sbc ui_tick_start
    cmp #50
    bcc wait_tick
    rts
.endproc

; Ekranu informacji lub bledu nie moze zamknac RETURN pozostaly po poprzedniej
; czynnosci. Odczekaj minimalny czas, wyczysc cien klawiatury i dopiero potem
; przyjmij nowe zdarzenie z K:.
.proc ui_wait_key
    jsr ui_delay_notice
    lda #$FF
    sta CH
    jmp ui_get_key
.endproc
