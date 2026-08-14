.include "os.inc"

; ---------------------------------------------------------------------------
; Warstwa logicznych operacji SIO
; ---------------------------------------------------------------------------
;
; Ten plik jest jedynym miejscem, w ktorym reszta programu buduje DCB
; (Device Control Block systemu Atari).  Procedury kopiujace nie musza wiec
; znac numerow komend stacji ani ukladu pol DCB: podaja jedynie numer stacji,
; numer sektora i dlugosc danych.
;
; Gotowy DCB nie trafia do systemowego wektora SIOV ($E459). sio_finish wywoluje
; hsio_auto, czyli niezalezny sterownik POKEY dolaczony w hsio_blob.s. Dzieki
; temu szybkosc nie zalezy od ROM-u Atari ani sterownika zainstalowanego przez
; DOS. Przy pierwszym rozkazie dla danej Dn: sterownik rozpoznaje rodzine
; protokolu, zapamietuje wynik, a przy bledzie moze wrocic do standardowego SIO.
;
; Konwencja wszystkich publicznych procedur:
;   wejscie: A = numer stacji 1..8;
;   wyjscie: C=0 sukces, C=1 blad; sio_result/DSTATS = kod statusu SIO.
; Procedury sektorowe dodatkowo czytaja sio_sector_* i sio_length_*.

.import hsio_auto
.import hsio_probe_once
.import hsio_speed_table

.export sio_status
.export sio_status_force
.export sio_hyperxf_track_info
.export sio_get_percom
.export sio_read_boot_sector
.export sio_probe_xf_dd
.export sio_read_sector
.export sio_write_sector
.export sio_write_percom
.export sio_format_disk
.export sio_clear_speeds
.export sio_get_mode
.export sio_result
.export sio_status_buf
.export sio_percom_buf
.export sio_sector_buf
.export sio_sector_lo
.export sio_sector_hi
.export sio_length_lo
.export sio_length_hi
.export sio_format_command
.export sio_actual_mode

.segment "BSS"
sio_result:      .res 1
sio_status_buf:  .res 4
sio_percom_buf:  .res 12
sio_sector_lo:   .res 1
sio_sector_hi:   .res 1
sio_length_lo:   .res 1
sio_length_hi:   .res 1
sio_format_command: .res 1
; Ostatnia predkosc, z ktora sterownik faktycznie zakonczyl rozkaz. Wlasny
; sterownik przechowuje ja w zgodnej z OS komorce MYSPEED=$3A; wartosc 40
; oznacza standard, 0..39 UltraSpeed, a pozostale kody inne rodziny turbo.
sio_actual_mode: .res 1

.segment "SCRATCH"
sio_sector_buf:  .res 512

.segment "CODE"

; Wspolny poczatek DCB. DDEVIC=$31 oznacza stacje dyskow, a DUNIT wybiera
; D1:..D8:. Wyzerowanie AUX jest istotne: nie kazda komenda nadpisuje oba
; bajty i pozostawiony numer sektora moglby zmienic znaczenie rozkazu.
; Wejscie: A = numer stacji (1..8).
.proc sio_begin
    sta DUNIT
    lda #$31
    sta DDEVIC
    lda #0
    sta DUNUSE
    sta DAUX1
    sta DAUX2
    rts
.endproc

; Wykonaj przygotowany DCB. hsio_auto uzywa tych samych pol $0300-$030B co
; systemowy SIOV, ale sam steruje liniami COMMAND, DATA OUT/IN i rejestrami
; szeregowymi POKEY. Po powrocie DSTATS zawiera $01 przy sukcesie albo kod
; bledu (np. timeout/NACK). Kopia w sio_result pozwala pokazac ten kod pozniej,
; kiedy DCB zostal juz przygotowany do nastepnej operacji.
.proc sio_finish
    ; Zawsze uzywaj dolaczonego sterownika POKEY. Aktywnie negocjuje profil
    ; stacji, ma wlasne ponowienia oraz powrot do predkosci standardowej, wiec
    ; dzialanie nie zalezy od poprawek SIO w ROM-ie systemowym.
    jsr hsio_auto
    ; Przejscie bezposrednio do wspolnego zapisu wyniku.
.endproc

.proc sio_capture_result
    ; Profil wykryty dla Dn: nie dowodzi jeszcze, ze konkretny sektor przeszedl
    ; szybko: po bledach sterownik moze ponowic go standardowo. Kopia MYSPEED
    ; zasila wskaznik FAST/STD na ekranie i pozwala odroznic opoznienie obrotowe
    ; od rzeczywistego powrotu protokolu do predkosci standardowej.
    lda $3A
    sta sio_actual_mode
    ldy DSTATS
    sty sio_result
    cpy #SIO_OK
    beq ok
    sec
    rts
ok:
    clc
    rts
.endproc

; Wyzeruj osiem uzywanych wpisow pamieci wykrytych predkosci. W sterowniku
; wartosc zero
; oznacza "jeszcze nie badano", dlatego nastepna komenda do kazdej stacji
; uruchomi pelna sekwencje Ultra/Turbo/XF/Warp. Wywolujemy to przed skanem,
; poniewaz uzytkownik mogl w miedzyczasie zmienic fizyczne numery urzadzen.
.proc sio_clear_speeds
    ldx #7
    lda #0
loop:
    sta hsio_speed_table,x
    dex
    bpl loop
    rts
.endproc

; Odczytaj profil zapamietany przez sterownik.
; Wejscie: A = DUNIT 1..8.
; Wyjscie: C=0, A = kod profilu; C=1, gdy stacja nie byla jeszcze badana.
;
; Tabela przechowuje kod+1, bo dzielnik UltraSpeed rowny 0 jest poprawna,
; najszybsza wartoscia i nie moze jednoczesnie oznaczac pustej pozycji.
; Kody po odjeciu jedynki:
;   $00..$3F = UltraSpeed, liczba jest dzielnikiem POKEY;
;   $40       = XF551 High Speed;
;   $41       = Happy 810 Warp;
;   $80       = 1050 Turbo;
;   $28       = standard (dzielnik 40).
.proc sio_get_mode
    tax
    lda hsio_speed_table-1,x
    beq unknown
    sec
    sbc #1
    clc
    rts
unknown:
    sec
    rts
.endproc

; STATUS ($53) zwraca cztery bajty. Pierwszy zawiera m.in. bity gestosci,
; ktorych geometry.s uzywa jako bezpiecznego planu B, gdy PERCOM nie dziala.
.proc sio_status
    jsr sio_begin
    jmp sio_status_finish
.endproc

; HyperXF bez czujnika klapki lub zmiany dysku moze zachowac w STATUS gestosc
; poprzedniego nosnika. AUX2=$55 ('U') wymusza sprawdzenie gestosci zgodnie z
; protokolem Stefana Dorndorffa. Osobny punkt wejscia jest konieczny, poniewaz
; zwykle stacje rozumieja jedynie klasyczne wyzerowane bajty AUX.
.proc sio_status_force
    jsr sio_begin
    lda #'U'
    sta DAUX2
    ; Przejscie bezposrednio do sio_status.
.endproc

.proc sio_status_finish
    lda #CMD_STATUS
    sta DCOMND
    lda #SIO_READ
    sta DSTATS
    lda #<sio_status_buf
    sta DBUFLO
    lda #>sio_status_buf
    sta DBUFHI
    lda #2
    sta DTIMLO
    lda #4
    sta DBYTLO
    lda #0
    sta DBYTHI
    jmp sio_finish
.endproc

; HyperXF GET TRACK INFO ($67), poziom analizy $20 (tylko naglowki sektorow).
; Procedura jest uzywana dopiero po rozpoznaniu HyperXF przez bajt 3 STATUS.
; main.s analizuje skrajne sciezki, aby potwierdzic pelna strone lub zakres
; nosnika 3,5 cala. W odroznieniu od GET PERCOM $4E komenda bada dyskietke,
; a nie ostatnia konfiguracje formatowania zapamietana przez stacje.
;
; Wejscie: A = numer stacji, X = logiczny numer sciezki 0..159.
; Wyjscie: standardowe C/status SIO; 128-bajtowy opis trafia do sector_buf.
.proc sio_hyperxf_track_info
    jsr sio_begin
    stx DAUX1
    lda #$20
    sta DAUX2
    lda #'g'
    sta DCOMND
    lda #SIO_READ
    sta DSTATS
    lda #<sio_sector_buf
    sta DBUFLO
    lda #>sio_sector_buf
    sta DBUFHI
    lda #8
    sta DTIMLO
    lda #128
    sta DBYTLO
    lda #0
    sta DBYTHI
    jmp sio_finish
.endproc

; GET PERCOM ($4E) pobiera 12-bajtowa konfiguracje stacji. Nie jest samodzielna
; identyfikacja nosnika: czesc firmware'ow zwraca ostatnio wybrany format, a
; XF551 nie rozroznia pewnie jednej i dwoch stron DD. main.s ustala klase przez
; READ 1 + STATUS, a w rozpoznanej rodzinie XF dodatkowo przez READ 4 + drugi
; STATUS. Dopiero potem sprawdza zgodnosc bloku. Liczba stron standardowego
; XF551 jest wyborem uzytkownika, poniewaz odczyt sektora granicznego nie
; rozstrzyga, czy znalezione tam stare dane naleza do biezacego formatu.
.proc sio_get_percom
    jsr sio_begin
    lda #CMD_PERCOM
    sta DCOMND
    lda #SIO_READ
    sta DSTATS
    lda #<sio_percom_buf
    sta DBUFLO
    lda #>sio_percom_buf
    sta DBUFHI
    lda #2
    sta DTIMLO
    lda #12
    sta DBYTLO
    lda #0
    sta DBYTHI
    jmp sio_finish
.endproc

; Bezpieczny test obecnosci nośnika: odczyt logicznego sektora startowego 1.
; Zgodnie z konwencja DOS/BIOS pierwsze trzy sektory maja zawsze 128 bajtow,
; takze na dyskach z sektorami 256 lub 512 bajtow.
.proc sio_read_boot_sector
    jsr sio_begin
    lda #CMD_READ
    sta DCOMND
    lda #SIO_READ
    sta DSTATS
    lda #<sio_sector_buf
    sta DBUFLO
    lda #>sio_sector_buf
    sta DBUFHI
    lda #4
    sta DTIMLO
    lda #128
    sta DBYTLO
    lda #0
    sta DBYTHI
    lda #1
    sta DAUX1
    jmp sio_finish
.endproc

; Jednorazowa prowokacja automatycznego wykrywania DD w standardowym XF551.
; Firmware tej stacji po odczycie sektorow 1..3 rozpoznaje jedynie MFM i
; domyslnie pozostaje w ED. Dopiero sektor 4 podlega kontroli "long sector":
; fizyczne 256 bajtow przelacza naped na DD, po czym ta sama komenda konczy sie
; pelna ramka 256 B. Prawdziwy ED wysyla tylko 128 B, wiec komputer oczekujacy
; 256 B dostaje kontrolowany timeout. Wynik tej komendy nie rozstrzyga niczego;
; main.s zawsze pobiera po niej nowy STATUS.
;
; Zwykle sio_finish celowo nie jest tu uzywane. Jego ponowienia i powrot do
; standardowej predkosci bylyby potrzebne dla transferu danych, lecz w ED
; wielokrotnie powtarzalyby oczekiwany timeout. DOHIDET z A=1/X=1 wykonuje
; dokladnie jedna probe i nadal przywraca POKEY, VBI oraz linie SIO.
.proc sio_probe_xf_dd
    jsr sio_begin
    lda #CMD_READ
    sta DCOMND
    lda #SIO_READ
    sta DSTATS
    lda #<sio_sector_buf
    sta DBUFLO
    lda #>sio_sector_buf
    sta DBUFHI
    lda #1
    sta DTIMLO
    lda #0
    sta DBYTLO
    lda #1
    sta DBYTHI
    lda #4
    sta DAUX1
    lda #1
    ldx #1
    jsr hsio_probe_once
    jmp sio_capture_result
.endproc

; Odczyt jednego sektora do wspolnego scratch $3E00-$3FFF. Numer i dlugosc sa
; rozdzielone, bo sektory 1..3 maja 128 bajtow, a dalsze rozmiar z PERCOM.
; buffer.s laczy pozniejsze przeniesienie danych do banku z surowym podgladem
; w wycentrowanym oknie; nie jest potrzebna osobna konwersja znakow.
.proc sio_read_sector
    jsr sio_begin
    lda #CMD_READ
    sta DCOMND
    lda #SIO_READ
    sta DSTATS
    jsr sio_set_sector_dcb
    jmp sio_finish
.endproc

; Zapis jednego sektora komenda PUT $50. Wczesniejsze $57 kazalo stacji po
; kazdym zapisie wykonac natychmiastowa weryfikacje, po czym program przy
; aktywnej opcji W i tak czytal cala dyskietke ponownie i porownywal bajty.
; $50 usuwa ten podwojny koszt; pelna weryfikacja programu pozostaje silniejsza,
; bo porownuje rzeczywiste dane celu z buforem zrodla.
.proc sio_write_sector
    jsr sio_begin
    lda #CMD_PUT
    sta DCOMND
    lda #SIO_WRITE
    sta DSTATS
    jsr sio_set_sector_dcb
    jmp sio_finish
.endproc

.proc sio_set_sector_dcb
    ; DBUF wskazuje na 512-bajtowy bufor wspolny. DTIMLO=4 daje stacji do
    ; czterech sekund; sterownik HSIO ma ponadto wlasne ponowienia transmisji.
    lda #<sio_sector_buf
    sta DBUFLO
    lda #>sio_sector_buf
    sta DBUFHI
    lda #4
    sta DTIMLO
    lda sio_length_lo
    sta DBYTLO
    lda sio_length_hi
    sta DBYTHI
    lda sio_sector_lo
    sta DAUX1
    lda sio_sector_hi
    sta DAUX2
    rts
.endproc

; SET PERCOM ($4F) przekazuje docelowej stacji geometrie zrodla. Musi zostac
; wykonany przed FORMAT, bo sam rozkaz formatujacy nie niesie 12 bajtow opisu.
.proc sio_write_percom
    jsr sio_begin
    lda #CMD_SET_PERCOM
    sta DCOMND
    lda #SIO_WRITE
    sta DSTATS
    lda #<sio_percom_buf
    sta DBUFLO
    lda #>sio_percom_buf
    sta DBUFHI
    lda #4
    sta DTIMLO
    lda #12
    sta DBYTLO
    lda #0
    sta DBYTHI
    jmp sio_finish
.endproc

; FORMAT ma kierunek "od stacji do komputera": po zakonczeniu stacja odsyla
; liste wadliwych sektorow. Dlatego DSTATS=SIO_READ, choc operacja fizycznie
; zapisuje cala dyskietke. $21 oznacza zwykly format, $22 format rozszerzony.
; Limit 180 sekund obejmuje wolne, prawdziwe mechanizmy i pelne 720 KB.
.proc sio_format_disk
    jsr sio_begin
    lda sio_format_command
    sta DCOMND
    lda #SIO_READ
    sta DSTATS
    lda #<sio_sector_buf
    sta DBUFLO
    lda #>sio_sector_buf
    sta DBUFHI
    lda #180
    sta DTIMLO
    lda sio_length_lo
    sta DBYTLO
    lda sio_length_hi
    sta DBYTHI
    jmp sio_finish
.endproc
