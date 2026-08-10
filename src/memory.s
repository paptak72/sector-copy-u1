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
.export memory_prepare_main_ram
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
saved_ramtop:       .res 1
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

; Zachowaj obszar strony zerowej programu wywolujacego, zanim uzyje go kopier.
; Umozliwia to pozniejszy powrot RTS do pozostawionego DOS-u.
.proc memory_save_environment
    lda PORTB
    sta saved_portb
    lda APPMHI
    sta saved_appmhi_lo
    lda APPMHI+1
    sta saved_appmhi_hi
    lda RAMTOP
    sta saved_ramtop
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

; PORTB=$FF wybiera podstawowy RAM dla CPU i ANTIC, pozostawia ROM systemu,
; wylacza SELF TEST oraz udostepnia RAM $A000-$BFFF zamiast ROM-u BASIC.
; Samo przelaczenie ROM-u nie zmienia mapy pamieci zapisanej przez OS podczas
; zimnego startu. RAMTOP=$C0 informuje E:, ze moze umiescic ekran w odzyskanym
; RAM-ie ponizej $C000. Bez tej zmiany start z wlaczonym BASIC-em konczyl sie
; czarnym ekranem, bo RAMTOP nadal mial wartosc $A0.
.proc memory_prepare_main_ram
    lda #MAIN_PORTB
    sta PORTB
    lda #$C0
    sta RAMTOP
    rts
.endproc

; Poinformuj procedury E:/S:, ze ekran i lista wyswietlania musza lezec ponad
; cala aplikacja. Bez APPMHI ponowne otwarcie E: mogloby umiescic ekran GR.0
; na kodzie programu albo danych tylko do odczytu.
.proc memory_reserve_application
    lda #<(__RODATA_RUN__ + __RODATA_SIZE__)
    sta APPMHI
    lda #>(__RODATA_RUN__ + __RODATA_SIZE__)
    sta APPMHI+1
    rts
.endproc

; Wykryj rezydentny DOS bez wywolywania procedur zaleznych od jego odmiany.
; SDX ma stala sygnature pod $0700. Dla innych DOS-ow wskaznik DOSVEC
; skierowany do RAM-u oznacza uruchomienie z rezydentnego srodowiska.
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

; Zachowaj rezydentny DOS. Destrukcyjne sondowanie bankow jest zabronione,
; poniewaz DOS albo RAM-dysk moze wykorzystywac pamiec rozszerzona.
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

; Odtworz stan DOS-u wywolujacego. Bezposrednio po tej procedurze nalezy
; wykonac RTS, dopoki pierwotny stos wywolania pozostaje poprawny.
.proc memory_restore_environment
    lda saved_portb
    sta PORTB
    lda saved_appmhi_lo
    sta APPMHI
    lda saved_appmhi_hi
    sta APPMHI+1
    lda saved_ramtop
    sta RAMTOP
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

; Wejscie po wybraniu trybu pelnego. Od tego miejsca aplikacja swiadomie nie
; wraca do programu ladujacego ani DOS-u.
.proc memory_takeover
    lda #0
    sta mem_keep_dos
    ; Ustaw stan pelnego RAM-u podstawowego: BASIC i SELF TEST sa wylaczone,
    ; a OS pozostaje w ROM-ie. Wymaga tego rowniez logika cienia PORTB w
    ; U1MB 576K/1088K.
    lda #MAIN_PORTB
    sta PORTB

    ; Programy ladujace XEX i DOS-y moga pozostawic odroczone wektory VBI oraz
    ; liczniki programowe w obszarze rezydentnym. Usun je przed przejeciem
    ; pamieci.
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

    ; Odlacz pozostawiona procedure PBI/DOS, aby nie przechwytywala operacji SIO.
    lda #0
    sta PDVMSK
    sta SHPDVS
    sta PDMSK

    ; Cieply start przez nadpisany DOS jest niebezpieczny. Skieruj DOSVEC do
    ; wektora zimnego startu systemu przed przejeciem obszaru rezydentnego.
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
    ; Czyszczenie konczy sie przed strona $36. Zakres $3600-$37FF zawiera
    ; segment AUXCODE z tekstami menu i procedurami paskow postepu, dlatego
    ; musi pozostac niezmieniony po zaladowaniu XEX-a. Nie nalezy on do
    ; bankowanego bufora danych.
    cmp #$36
    bcc clear_dos

    ; Kopier przejmuje pamiec podstawowa od $0700. Bufor bankowany wykorzystuje
    ; ciagle okno pamieci glownej $4000-$7FFF.
    lda #<$0700
    sta MEMLO
    lda #>$0700
    sta MEMLO+1
    jmp memory_build_bank_list
.endproc

; Punkt wejscia zgodnosci uzywany przez interfejs.
.proc memory_probe
    jmp memory_build_bank_list
.endproc

; Zbadaj wszystkie selektory PORTB mozliwe w ukladzie RAMBO 1088K. Dwufazowy
; test sygnatur automatycznie scala aliasy na maszynach 64K, 130XE, 320K i
; 576K: sygnature zachowuje tylko ostatni selektor danego fizycznego banku.
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

    ; Glowne okno $4000-$7FFF jest zawsze pierwszym bankiem bufora 16 KB.
    lda #MAIN_PORTB
    sta mem_bank_indices
    lda #1
    sta mem_usable_banks

    ; Zapisz unikalna czterobajtowa sygnature przez wszystkie 64 selektory.
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

    ; Jesli selektor rozszerzenia jest aliasem glownego RAM-u, zapamietaj go,
    ; aby nie policzyc glownego okna dwukrotnie.
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

    ; Wyznacz maske bitow selektora pokazywana w diagnostyce pamieci.
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

; Zachowawcza mapa bufora dla trybu rezydentnego DOS-u. Obraz programu zaczyna
; sie od $8000, dlatego $4000-$7FFF jest bezpiecznym oknem tylko wtedy, gdy
; MEMLO do niego nie dochodzi. Pamiec rozszerzona nie jest tutaj dotykana.
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

; Laczna liczba blokow 128 B dostepnych dla bufora strumieniowego.
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

; Przepisz bity 0..5 probe_index na bity 1,2,3,5,6,7 rejestru PORTB.
; Bit 4 pozostaje wyzerowany (okno CPU wlaczone), a bit 0 ustawiony (ROM OS).
; Bit 1 w zwyklym XL/XE steruje BASIC-em, lecz rozszerzenia 1088K dekoduja go
; takze jako czesc numeru banku. Nie wolno wymuszac go podczas sondy, bo
; zmniejszyloby to wykryty bufor U1MB o polowe. Po kazdym dostepie bankowym
; memory_restore_bank przywraca MAIN_PORTB=$FF i BASIC pozostaje wylaczony.
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

; C=0, gdy $4000-$4003 zawiera poprawna sygnature sondy.
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

; Wejscie: A = indeks od zera w tablicy mem_bank_indices.
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

; Odtworzenie glownego mapowania jest wywolywane po kazdym fragmencie bufora.
; Szesc bajtow miesci sie dokladnie w wolnej koncowce UICODE pod $3E00.
.segment "UICODE"
.proc memory_restore_bank
    lda #MAIN_PORTB
    sta PORTB
    rts
.endproc
.segment "CODE"
