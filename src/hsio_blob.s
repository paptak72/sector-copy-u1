; ---------------------------------------------------------------------------
; Niezalezny sterownik Highspeed SIO 1.33
; ---------------------------------------------------------------------------
;
; Sector Copy U1 uzywa sprawdzonej implementacji Matthiasa Reichla
; (HiassofT), GPL-2.0-or-later. Sterownik rozmawia bezposrednio z POKEY-em;
; nie jest wywolaniem ani latka systemowego SIOV. Obraz o stalym adresie
; zbudowano ze zrodel https://github.com/HiassofT/highspeed-sio poleceniem:
;
;   atasm -dFASTVBI -dMAXDRIVENO=8 -dSTART=$3985 ... hisio.src
;
; Biblioteka i aplikacja zostaly ograniczone do D1:..D8:. FASTVBI instaluje na
; czas transmisji bardzo krotka obsluge VBI; bez niej przerwanie obrazu mogloby
; zabrac POKEY-owi bajt przy dzielnikach 0/1 (predkosci ponad 100 kbit/s).
;
; Co dzieje sie przy pierwszym dostepie do danej Dn:
;   1. standardowa komenda $3F pyta o dzielnik UltraSpeed;
;   2. jesli nie odpowie, STATUS jest probowany jako 1050 Turbo;
;   3. potem jako XF551 High Speed;
;   4. na koncu probowany jest Happy 810 Warp;
;   5. brak odpowiedzi turbo zapisuje profil standardowy (dzielnik $28).
;
; Wynik+1 laduje w hsio_speed_table. Kolejne sektory omijaja wykrywanie i ida
; od razu wybranym protokolem. Rozne rodziny nie roznia sie tylko dzielnikiem:
; UltraSpeed wysyla juz ramke rozkazu szybko, 1050 Turbo ustawia bit 7 DAUX2,
; XF551 bit 7 DCOMND, a Happy Warp bit 5 DCOMND. Przy bledzie szybki transfer
; jest ponawiany, a druga seria prob odbywa sie standardowo.
;
; Plik ATASM ma szesc bajtow naglowka XEX. Parametry .incbin pomijaja naglowek
; i wstawiaja w segment HSIO dokladnie 901 bajtow kodu $3985-$3D09. Asercje
; ponizej chronia przed cichym przesunieciem punktow wejscia po zmianie pliku.

.export hsio_auto
.export hsio_direct
.export hsio_probe_once
.export hsio_speed_table

hsio_auto        = $3985
hsio_direct      = $399E
; Wewnetrzne wejscie DOHIDET jest jawnie opisane w hisiocode-main.src. A=1
; wybiera jedna probe bez powrotu do innej predkosci, a X=1 jedna probe ramki
; rozkazu. Uzywamy go tylko do kontrolowanego READ 4 w XF551, gdzie poprawna
; dyskietka ED celowo wysle krotsza ramke i zwykle wejscie ponawialoby ten
; oczekiwany timeout przez kilka sekund.
hsio_probe_once  = $3A3F
hsio_speed_table = $3D02

; hsio_auto: glowny punkt wejscia. Rozpoznaje nieznana stacje, potem wykonuje
; DCB. hsio_direct: wejscie dla juz wybranego kodu predkosci. hsio_probe_once:
; jednokrotne wykonanie z predkoscia ustalona przez poprzedni rozkaz.
; speed_table: osiem bajtow, po jednym dla D1:..D8:, kodowanych jako tryb+1.

.segment "HSIO"
    .assert * = hsio_auto, error, "unexpected HSIO load address"
    .incbin "hsio-1.33-3985-max8.bin", 6, 901
    .assert * = $3D0A, error, "unexpected HSIO payload size"
