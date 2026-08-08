# HyperXF — wykrywanie gęstości i geometrii

Ten dokument opisuje decyzje implementacyjne w Sector Copy U1 0.6.6. Źródłem
protokołu jest instrukcja **Hyper+ XF 1.0** Stefana Dorndorffa:

- <https://ftp.pigwa.net/stuff/collections/nir_dary_cds/Hardware%20Info/HyperXF/Manual/Anleitung.txt>

## Dlaczego GET PERCOM nie wystarcza

W zwykłym urządzeniu odpowiedź komendy GET PERCOM `$4E` bywa opisem aktualnego
nośnika. HyperXF zwraca jednak blok ostatnio ustawiony komendą SET PERCOM
`$4F`. Po zapisaniu 720 KB stacja może więc nadal zgłaszać wcześniejsze
`40T/1S`, mimo że zwykłe komendy `R/P/W` udostępniają sektory aż do `$0B40`.
Program rozpoznaje HyperXF po trzecim bajcie STATUS równym `$D9` i dla takiego
urządzenia nie bierze liczby ścieżek ani stron z GET PERCOM.

## Kolejność badania

1. Zwykły READ sektora 1 uruchamia w stacji klasyczne rozpoznawanie gęstości.
2. STATUS odczytuje wynik; w HyperXF dodatkowy STATUS z `AUX2='U'` wymusza
   sprawdzenie także bez czujnika zmiany dyskietki.
3. Pierwszy bajt STATUS wybiera SD (18×128), MD (26×128) albo DD (18×256).
4. Czwarty bajt STATUS podaje typ mechanizmu w bicie 6 oraz tryb
   `A/B/C/D/M/F/S/X` w bitach 0-2.
5. Komenda GET TRACK INFO `$67`, `AUX2=$20`, odczytuje 128-bajtowy opis
   nagłówków wskazanej ścieżki logicznej.
6. Po sondach wykonywany jest ponownie STATUS `U`, ponieważ nieudana próba
   ścieżki każe firmware ponownie zbadać gęstość przy następnym dostępie.

## Granice logiczne

HyperXF numeruje ścieżki logiczne kolejno przez strony nośnika:

- 5,25 cala: 0-39 oraz 40-79;
- 3,5 cala: 0-79 oraz 80-159.

Sector Copy wymaga poprawnych par początku i końca każdego deklarowanego
zakresu. Dla 40T/1S bada 0 i 39. Pełne 5,25 cala wymaga dodatkowo 40 i 79,
a pełne 3,5 cala także 80 i 159. Sam ślad na końcu nie jest dowodem: mógł
pozostać po dawnym formatowaniu.

Tryby `A/B/C/D` są zawsze traktowane jako jawny widok partycji 40T/1S. Tryby
`M/F/S/X` mogą zostać rozszerzone tylko wtedy, gdy rzeczywiste ścieżki tworzą
pełny, ciągły zestaw.

## Walidacja odpowiedzi `$67`

Sukces transmisji oznacza tylko odebranie 128 bajtów. Tablica sektorów mieści
się w bajtach 12-56 i kończy zerem. Każdy wpis zawiera numer w bitach 0-4 oraz
stan w bitach 5-7. Walidator wymaga:

- dokładnie jednego kompletu 1-18 dla SD/DD albo 1-26 dla MD;
- braku zera przed końcem kompletu;
- braku duplikatów i numerów spoza zakresu;
- stanu poprawnego sektora (`$00` lub `$E0` w górnych bitach).
- pomijania specjalnego wpisu `$C0`, który oznacza fizyczną przerwę, a nie
  sektor ani błąd. Odrzucanie `$C0` było przyczyną wyniku `40T/1S` dla
  poprawnego nośnika 720 KB.

Cztery nieużywane już bajty początku odebranego bloku są wykorzystywane jako
32-bitowa mapa numerów sektorów, dzięki czemu kontrola nie zużywa dodatkowej
pamięci stałej Atari.

Jeśli początek/koniec zakresu jest uszkodzony albo odpowiedzi są sprzeczne,
stacja pozostaje widoczna w menu, lecz nośnik dostaje znacznik niejednoznacznej
geometrii. Nie może wtedy zostać użyty jako źródło. To celowe: skopiowanie
jedynie pierwszych 720 sektorów pełnej dyskietki byłoby pozornym sukcesem i
prowadziłoby do cichej utraty danych.

## Trzy gęstości, pięć typowych formatów

Nie istnieje dziewięć gęstości. Gęstości zapisu są trzy: SD, MD/ED i DD.
Pięć powszechnie spotykanych formatów Małego Atari to 90, 130, 180, 360 oraz
720 KB. Cztery pozostałe pola poniższej tabeli są matematycznymi połączeniami
SD/MD z pełnym nośnikiem 5,25 lub 3,5 cala. Instrukcja HyperXF jawnie zezwala
formatować każdą z trzech gęstości jedno- albo dwustronnie, dlatego detektor je
rozumie, lecz interfejs nie nazywa ich nowymi gęstościami.

| Zakres | SD | MD | DD |
|---|---:|---:|---:|
| 40T/1S | **720×128 = 90 KB** | **1040×128 = 130 KB** | **720×256 = 180 KB** |
| 40T/2S, 5,25 cala | 1440×128 = 180 KB | 2080×128 = 260 KB | **1440×256 = 360 KB** |
| 80T/2S, 3,5 cala | 2880×128 = 360 KB | 4160×128 = 520 KB | **2880×256 = 720 KB** |

Pierwsze trzy sektory logiczne nośnika DD są przez Atari przesyłane po 128
bajtów; nie zmienia to liczby sektorów ani geometrii.

## Przeplot i szybkie SIO

Standardowe komendy formatowania `$21/$22` wysłane do HyperXF w UltraSpeed
automatycznie wybierają przeplot zoptymalizowany dla UltraSpeed. Sector Copy
nie ustawia stanowych bitów HyperSpeed. Korzysta z własnego sterownika POKEY,
a po formatowaniu pokazuje, czy sama komenda zakończyła się jako `FAST`, czy po
fallbacku jako `STD`.
