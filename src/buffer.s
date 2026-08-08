.include "os.inc"

; ---------------------------------------------------------------------------
; Strumien danych w bankowanej pamieci rozszerzonej
; ---------------------------------------------------------------------------
;
; Atari widzi naraz tylko jedno 16-kilobajtowe okno rozszerzonej pamieci pod
; $4000-$7FFF. memory.s wykrywa fizyczne banki i zapisuje odpowiadajace im
; wartosci PORTB w mem_bank_indices. Ten modul przedstawia wszystkie te okna
; jako jeden ciag bajtow:
;
;   (buffer_bank_slot, buffer_addr_hi:lo)
;       bank 0: $4000 ... $7FFF, bank 1: $4000 ... $7FFF, itd.
;
; Gdy adres dojdzie do $8000, normalize_position przechodzi do nastepnego
; banku i wraca na $4000. Po kazdym fragmencie przywracana jest pamiec glowna,
; zeby kod, ekran i system operacyjny nigdy nie wykonywaly sie z przypadkowo
; wlaczonym bankiem. Wszystkie operacje przesuwaja ten sam kursor strumienia;
; wywolujacy robi buffer_reset przed odczytem, zapisem lub weryfikacja porcji.
;
; Dlugosc brana jest z sio_length_lo/hi. To wazne dla geometrii DD: sektory
; 1..3 maja po 128 bajtow, a nastepne po 256 (lub 512) bajtow.

.import memory_select_bank
.import memory_restore_bank
.import mem_usable_banks
.import sio_length_lo
.import sio_length_hi
.import sio_sector_buf

.export buffer_reset
.export buffer_store
.export buffer_load
.export buffer_compare
.export buffer_bank_slot
.export buffer_addr_lo
.export buffer_addr_hi

.segment "ZEROPAGE"
buffer_data_ptr: .res 2
buffer_win_ptr:  .res 2

.segment "BSS"
buffer_bank_slot: .res 1
buffer_addr_lo:   .res 1
buffer_addr_hi:   .res 1
buffer_len_lo:    .res 1
buffer_len_hi:    .res 1

.segment "CODE"

; Ustaw kursor na pierwszym bajcie pierwszego wykrytego banku.
; Funkcja nie wlacza jeszcze banku i nie modyfikuje PORTB.
.proc buffer_reset
    lda #0
    sta buffer_bank_slot
    sta buffer_addr_lo
    lda #$40
    sta buffer_addr_hi
    rts
.endproc

; Porownaj kolejny sektor strumienia bezposrednio z sio_sector_buf.
; Wejscie: dlugosc w sio_length_*, kursor ustawiony na poczatek sektora.
; Wyjscie: C=0 wszystkie bajty rowne, C=1 roznica lub koniec pamieci.
;
; Kursor przesuwa sie tak samo jak w buffer_load, ale porownanie bezposrednie
; nie wymaga drugiego bufora 512 B. Jedyny obszar $3E00-$3FFF moze dzieki temu
; sluzyc wszystkim operacjom sektorowym, a HSIO miesci sie ponizej okna $4000.
.proc buffer_compare
    lda #<sio_sector_buf
    sta buffer_data_ptr
    lda #>sio_sector_buf
    sta buffer_data_ptr+1
    lda sio_length_lo
    sta buffer_len_lo
    lda sio_length_hi
    sta buffer_len_hi
    jsr normalize_position
    bcs failed
    lda buffer_bank_slot
    jsr memory_select_bank
    bcs failed

compare_block:
    ; Wszystkie obslugiwane sektory i pozycje strumienia sa wyrownane do 128 B.
    ; Kopiowanie pol strony petla Y=0..127 ogranicza przelaczanie bankow oraz
    ; aktualizacje 16-bitowych licznikow do jednego razu na blok. Krotki czas
    ; obslugi sektora pozwala zachowac okno wynikajace z przeplotu HyperXF.
    ldy #0
compare_byte:
    lda (buffer_win_ptr),y
    cmp (buffer_data_ptr),y
    bne mismatch
    iny
    bpl compare_byte
    jsr advance_block
    jsr decrement_block
    lda buffer_len_lo
    ora buffer_len_hi
    beq complete
    lda buffer_addr_hi
    cmp #$80
    bne compare_block

    ; Przed zmiana banku koniecznie wracamy do pamieci glownej. Dopiero
    ; normalize_position wybierze nastepny logiczny bank i zbuduje wskaznik.
    jsr memory_restore_bank
    jsr normalize_position
    bcs failed
    lda buffer_bank_slot
    jsr memory_select_bank
    bcs failed
    jmp compare_block

complete:
    jsr memory_restore_bank
    clc
    rts
mismatch:
    jsr memory_restore_bank
failed:
    sec
    rts
.endproc

; Dopisz sektor do strumienia.
; Wejscie: A/Y = mlodszy/starszy bajt adresu zrodla, dlugosc w sio_length_*.
; Wyjscie: C=0 sukces, C=1 brak nastepnego banku.
; Dlugosc nie jest czytana z DCB: ten moze jeszcze opisywac poprzedni STATUS
; lub PERCOM, zanim procedura kopiujaca przygotuje kolejna operacje SIO.
.proc buffer_store
    sta buffer_data_ptr
    sty buffer_data_ptr+1
    lda sio_length_lo
    sta buffer_len_lo
    lda sio_length_hi
    sta buffer_len_hi
    jsr normalize_position
    bcs failed
    lda buffer_bank_slot
    jsr memory_select_bank
    bcs failed

copy_block:
    ldy #0
copy_byte:
    lda (buffer_data_ptr),y
    sta (buffer_win_ptr),y
    iny
    bpl copy_byte
    jsr advance_block
    jsr decrement_block
    lda buffer_len_lo
    ora buffer_len_hi
    beq complete
    lda buffer_addr_hi
    cmp #$80
    bne copy_block

    jsr memory_restore_bank
    jsr normalize_position
    bcs failed
    lda buffer_bank_slot
    jsr memory_select_bank
    bcs failed
    jmp copy_block

complete:
    jsr memory_restore_bank
    clc
    rts
failed:
    sec
    rts
.endproc

; Pobierz sektor ze strumienia.
; Wejscie: A/Y = adres celu, dlugosc w sio_length_*.
; Wyjscie: C=0 sukces, C=1 koniec dostepnych bankow.
.proc buffer_load
    sta buffer_data_ptr
    sty buffer_data_ptr+1
    lda sio_length_lo
    sta buffer_len_lo
    lda sio_length_hi
    sta buffer_len_hi
    jsr normalize_position
    bcs failed
    lda buffer_bank_slot
    jsr memory_select_bank
    bcs failed

copy_block:
    ldy #0
copy_byte:
    lda (buffer_win_ptr),y
    sta (buffer_data_ptr),y
    iny
    bpl copy_byte
    jsr advance_block
    jsr decrement_block
    lda buffer_len_lo
    ora buffer_len_hi
    beq complete
    lda buffer_addr_hi
    cmp #$80
    bne copy_block

    jsr memory_restore_bank
    jsr normalize_position
    bcs failed
    lda buffer_bank_slot
    jsr memory_select_bank
    bcs failed
    jmp copy_block

complete:
    jsr memory_restore_bank
    clc
    rts
failed:
    sec
    rts
.endproc

.proc normalize_position
    ; $8000 jest znacznikiem konca okna, a nie poprawnym adresem bufora.
    ; Przejscie banku nastepuje tylko miedzy bajtami, nigdy w polowie dostepu.
    lda buffer_addr_hi
    cmp #$80
    bne set_pointer
    inc buffer_bank_slot
    lda #0
    sta buffer_addr_lo
    lda #$40
    sta buffer_addr_hi
set_pointer:
    lda buffer_bank_slot
    cmp mem_usable_banks
    bcs unavailable
    ; buffer_bank_slot jest pozycja w uporzadkowanej tablicy bankow, nie
    ; surowa wartoscia PORTB. memory_select_bank wykona wlasciwe mapowanie.
    lda buffer_addr_lo
    sta buffer_win_ptr
    lda buffer_addr_hi
    sta buffer_win_ptr+1
    clc
    rts
unavailable:
    sec
    rts
.endproc

.proc advance_block
    ; Przesun oba wskazniki o 128 bajtow. buffer_addr_* jest trwalym kursorem,
    ; a buffer_win_ptr jego aktualnym adresem w wybranym oknie PORTB.
    lda buffer_data_ptr
    clc
    adc #128
    sta buffer_data_ptr
    bcc :+
    inc buffer_data_ptr+1
:
    lda buffer_addr_lo
    clc
    adc #128
    sta buffer_addr_lo
    sta buffer_win_ptr
    lda buffer_addr_hi
    adc #0
    sta buffer_addr_hi
    sta buffer_win_ptr+1
    rts
.endproc

.proc decrement_block
    ; Dlugosci 128/256/512 sa wielokrotnosciami 128, wiec jedno 16-bitowe
    ; odejmowanie aktualizuje licznik calego przetworzonego bloku.
    lda buffer_len_lo
    sec
    sbc #128
    sta buffer_len_lo
    lda buffer_len_hi
    sbc #0
    sta buffer_len_hi
    rts
.endproc
