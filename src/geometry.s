.include "os.inc"

; ---------------------------------------------------------------------------
; Opis stacji, geometrii nosnika i wykrytego protokolu SIO
; ---------------------------------------------------------------------------
;
; Kazda tablica ma 8 pozycji: indeks 0 opisuje D1:, indeks 7 D8:.
; Rozdzielenie danych na osobne tablice pol jest na 6502 mniejsze i szybsze
; niz mnozenie indeksu przez rozmiar struktury.
;
; Geometria zwyklych stacji pochodzi najpierw z GET PERCOM ($4E). Gdy starsza
; stacja nie zna PERCOM, geo_set_fallback interpretuje pierwszy bajt STATUS i
; tworzy jeden z klasycznych formatow SD/ED/DD. HyperXF jest wyjatkiem: jego
; PERCOM zwraca ostatnia konfiguracje ustawiona komenda O, a nie opis nosnika.
; main.s wymusza wiec STATUS U i bada rzeczywiste naglowki sciezek komenda $67,
; co pozwala rozpoznac wszystkie formaty od 90 KB do 720 KB bez zgadywania.
;
; Liczba sektorow jest 16-bitowa i wynosi tracks * sides * sectors-per-track.
; Rozmiar obrazu nie jest po prostu total*bps: sektory startowe 1..3 maja
; zawsze 128 bajtow; uwzglednia to modul copy.s przy liczeniu bankow.

.import sio_status_buf
.import sio_percom_buf

.export geo_clear
.export geo_set_fallback
.export geo_set_percom
.export geo_set_speed
.export geo_calculate_total

.export geo_present
.export geo_tracks
.export geo_sides
.export geo_spt_lo
.export geo_spt_hi
.export geo_bps_lo
.export geo_bps_hi
.export geo_density
.export geo_total_lo
.export geo_total_hi
.export geo_speed_kind
.export geo_speed_div
.export geo_percom_ok

MAX_DRIVES = 8

.segment "BSS"
geo_present:     .res MAX_DRIVES
geo_tracks:      .res MAX_DRIVES
geo_sides:       .res MAX_DRIVES
geo_spt_lo:      .res MAX_DRIVES
geo_spt_hi:      .res MAX_DRIVES
geo_bps_lo:      .res MAX_DRIVES
geo_bps_hi:      .res MAX_DRIVES
geo_density:     .res MAX_DRIVES
geo_total_lo:    .res MAX_DRIVES
geo_total_hi:    .res MAX_DRIVES
geo_speed_kind:  .res MAX_DRIVES ; 0=standard, 1=Ultra, 2=XF, 3=Turbo, 4=Warp
geo_speed_div:   .res MAX_DRIVES
geo_percom_ok:   .res MAX_DRIVES

mul_lo:          .res 1
mul_hi:          .res 1
mul_count:       .res 1
drive_index:     .res 1

.segment "CODE"

.proc geo_clear
    ; Czyszczenie jednym X pozwala zachowac identyczny indeks we wszystkich
    ; tablicach. geo_present=0 jest nadrzednym znacznikiem pustego wpisu.
    ldx #MAX_DRIVES-1
    lda #0
loop:
    sta geo_present,x
    sta geo_tracks,x
    sta geo_sides,x
    sta geo_spt_lo,x
    sta geo_spt_hi,x
    sta geo_bps_lo,x
    sta geo_bps_hi,x
    sta geo_density,x
    sta geo_total_lo,x
    sta geo_total_hi,x
    sta geo_speed_kind,x
    sta geo_speed_div,x
    sta geo_percom_ok,x
    dex
    bpl loop
    rts
.endproc

; Plan awaryjny na podstawie STATUS.
; Wejscie: X = indeks stacji 0..7, sio_status_buf zawiera odpowiedz $53.
;
; Bit 7 pierwszego bajtu oznacza enhanced density (26x128), a bit 5 double
; density (18x256). Brak obu oznacza single density (18x128). Wszystkie trzy
; profile zakladaja 40 sciezek i jedna strone, bo STATUS nie przekazuje tych
; wielkosci. geo_percom_ok pozostaje zerem, co widac w menu jako profil F.
.proc geo_set_fallback
    lda #1
    sta geo_present,x
    lda #40
    sta geo_tracks,x
    lda #1
    sta geo_sides,x
    lda #0
    sta geo_spt_hi,x
    sta geo_bps_hi,x
    sta geo_percom_ok,x
    sta geo_speed_kind,x
    sta geo_density,x
    lda #40
    sta geo_speed_div,x

    lda sio_status_buf
    bmi enhanced
    and #$20
    bne double

single:
    lda #18
    sta geo_spt_lo,x
    lda #128
    sta geo_bps_lo,x
    jmp calculate

enhanced:
    lda #26
    sta geo_spt_lo,x
    lda #128
    sta geo_bps_lo,x
    lda #4
    sta geo_density,x
    jmp calculate

double:
    lda #18
    sta geo_spt_lo,x
    lda #0
    sta geo_bps_lo,x
    lda #1
    sta geo_bps_hi,x
    lda #4
    sta geo_density,x

calculate:
    jmp geo_calculate_total
.endproc

; Zinterpretuj 12-bajtowy blok PERCOM.
; Wejscie: X = indeks stacji, sio_percom_buf = odpowiedz komendy $4E.
; Wyjscie: C=0 profil przyjety, C=1 dane nielogiczne/nieobslugiwany sektor.
;
; Uzywane pola PERCOM:
;   +0      liczba sciezek;
;   +2..+3 sektory na sciezke (big endian: starszy, mlodszy);
;   +4      indeks ostatniej strony, dlatego liczba stron = wartosc+1;
;   +5      metoda/gestosc zapisu przekazywana z powrotem przy formatowaniu;
;   +6..+7 bajty na sektor (big endian).
; Akceptujemy 128, 256 i 512. Jawna walidacja chroni mnozenie i petle kopiujace
; przed przypadkowa odpowiedzia urzadzenia, ktore nie implementuje PERCOM.
.proc geo_set_percom
    lda sio_percom_buf
    beq invalid
    lda sio_percom_buf+4
    cmp #2
    bcs invalid
    lda sio_percom_buf+2
    ora sio_percom_buf+3
    beq invalid

    ; Akceptowane rozmiary sektora: 128, 256 i 512 bajtow.
    lda sio_percom_buf+6
    beq check_128
    cmp #1
    beq check_256
    cmp #2
    beq check_512
    bne invalid
check_128:
    lda sio_percom_buf+7
    cmp #128
    bne invalid
    beq accepted
check_256:
    lda sio_percom_buf+7
    bne invalid
    beq accepted
check_512:
    lda sio_percom_buf+7
    bne invalid

accepted:
    lda sio_percom_buf
    sta geo_tracks,x
    lda sio_percom_buf+4
    clc
    adc #1
    sta geo_sides,x
    lda sio_percom_buf+3
    sta geo_spt_lo,x
    lda sio_percom_buf+2
    sta geo_spt_hi,x
    lda sio_percom_buf+7
    sta geo_bps_lo,x
    lda sio_percom_buf+6
    sta geo_bps_hi,x
    lda sio_percom_buf+5
    sta geo_density,x
    lda #1
    sta geo_percom_ok,x
    jsr geo_calculate_total
    clc
    rts
invalid:
    sec
    rts
.endproc

; Przepisz wewnetrzny kod sterownika na dane czytelne dla interfejsu.
; Wejscie: X = indeks stacji, A = aktywnie wykryty kod Highspeed SIO.
;
; $00-$3F to UltraSpeed (A jest dzielnikiem POKEY), $40 to XF551, $41 Happy
; Warp, a $80 to 1050 Turbo. $28 oznacza brak turbo, poniewaz 40 jest
; standardowym dzielnikiem. Rodziny XF/Turbo/Warp maja stale efektywne
; dzielniki 16/6/16, wiec zapisujemy je osobno dla ekranu diagnostycznego.
;
; Sama wartosc dzielnika nie jest nazwa konkretnego modelu. HyperXF, Tygrys,
; FujiNet i SIO2SD moga wszystkie odpowiedziec w rodzinie UltraSpeed; menu
; uczciwie pokazuje protokol i dzielnik (np. US10), nie zgaduje producenta.
.proc geo_set_speed
    cmp #40
    beq standard
    cmp #$40
    beq xf
    cmp #$41
    beq warp
    cmp #$80
    beq turbo
    ; Wszystkie pozostale legalne wartosci sa dzielnikami UltraSpeed.
    ; Porownanie musi byc bezposrednie: po CMP #$41 wartosc $80 daje wynik $3F
    ; i wyzerowany znacznik N, dlatego BMI nie rozpoznaloby kodu 1050 Turbo.
    sta geo_speed_div,x
    lda #1
    sta geo_speed_kind,x
    rts
xf:
    lda #16
    sta geo_speed_div,x
    lda #2
    sta geo_speed_kind,x
    rts
turbo:
    lda #6
    sta geo_speed_div,x
    lda #3
    sta geo_speed_kind,x
    rts
warp:
    lda #16
    sta geo_speed_div,x
    lda #4
    sta geo_speed_kind,x
    rts
standard:
    lda #0
    sta geo_speed_kind,x
    lda #40
    sta geo_speed_div,x
    rts
.endproc

; Wejscie: X = indeks stacji. Oblicza 16-bitowe tracks*spt*sides.
.proc geo_calculate_total
    stx drive_index
    lda #0
    sta mul_lo
    sta mul_hi
    lda geo_tracks,x
    sta mul_count
add_track:
    lda mul_lo
    clc
    adc geo_spt_lo,x
    sta mul_lo
    lda mul_hi
    adc geo_spt_hi,x
    sta mul_hi
    dec mul_count
    bne add_track

    lda geo_sides,x
    cmp #2
    bne store
    asl mul_lo
    rol mul_hi
store:
    lda mul_lo
    sta geo_total_lo,x
    lda mul_hi
    sta geo_total_hi,x
    rts
.endproc
