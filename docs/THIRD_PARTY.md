# Składniki zewnętrzne

## Highspeed SIO 1.33

Sector Copy U1 zawiera kod Highspeed SIO autorstwa Matthiasa Reichla
(HiassofT), Copyright © 2003–2023. Oryginalne źródła:

- repozytorium: <https://github.com/HiassofT/highspeed-sio>;
- wydanie: tag `1.33`;
- commit: `5b3e4f1efe307244ede98be365b846552ae303fa`;
- licencja: GNU General Public License, wersja 2 lub — według wyboru — dowolna
  późniejsza (`GPL-2.0-or-later`).

Niezmieniony komplet plików źródłowych tego wydania, wraz z oryginalnymi
informacjami o autorze i tekstem licencji, jest dołączony w katalogu:

```text
third_party/highspeed-sio-1.33/
```

Nie jest to kod napisany dla Sector Copy U1. Projekt korzysta z niego jako
zewnętrznego silnika transmisji SIO przez POKEY. Napisane dla Sector Copy U1
są warstwa wywołań sterownika, zapamiętywanie profilu każdej stacji,
prezentacja rzeczywistego trybu `FAST`/`STD`, logika kopiowania oraz dodatkowe
rozpoznawanie urządzenia i geometrii HyperXF.

Standardowa ścieżka wywołuje główne wejście automatyczne. Sonda gęstości
XF551 korzysta ponadto z opisanego w oryginalnym `hisiocode-main.src` wejścia
`DOHIDET`: parametry A=1 i X=1 wykonują jedną próbę bez zmiany prędkości, ale
z pełnym sprzątaniem POKEY i VBI. Jest to potrzebne, ponieważ prawidłowy ED
celowo zwraca dla `READ 4/256` krótszą ramkę; zwykłe ponowienia powtarzałyby
oczekiwany timeout. Adres `$3A3F` wynika dokładnie z wymienionego niżej buildu
`START=$3985` i jest kontrolowany przez testy mapy oraz źródeł.

Do programu dołączony jest plik:

```text
src/hsio-1.33-3985-max8.bin
```

Parametry kompilacji różnią się od domyślnych wyłącznie konfiguracją miejsca
i liczby stacji:

```sh
cd third_party/highspeed-sio-1.33
atasm -dFASTVBI -dMAXDRIVENO=8 '-dSTART=$3985' \
  -o../../src/hsio-1.33-3985-max8.bin hisio.src
```

- `START=$3985` — stały obszar między stanem programu a buforem sektorowym;
- `MAXDRIVENO=8` — tabela profili i Sector Copy U1 obsługują D1:–D8:;
- `FASTVBI` — krótka obsługa VBI bezpieczna przy bardzo małych dzielnikach
  POKEY.

Wygenerowany plik ma 907 bajtów: 6-bajtowy nagłówek ATASM i 901 bajtów kodu.
`hsio_blob.s` pomija nagłówek i ładuje kod do `$3985-$3D09`.

```text
SHA-256:
7ba8de340671c1e886d8c04e6e0733cd2978a57a47a6229ecc38cdfcd11f1db3
```

`make test` sprawdza rozmiar, sumę oraz adresy punktów wejścia. W razie zmiany
źródeł lub parametrów suma musi zostać świadomie zaktualizowana, a wszystkie
protokoły ponownie sprawdzone.

## Pozostała część programu

Poza wyżej wskazanym modułem Highspeed SIO kod wynikowy nie zawiera procedur
przeniesionych z QMEG-a, DOS-ów, ROM-ów stacji ani innych kopierów. Standardowe
rejestry Atari OS, POKEY i PORTB oraz komendy SIO, STATUS i PERCOM są
interfejsami platformy, nie skopiowanymi modułami programu. Materiały te służą
do dokumentacji zgodności i testów, ale nie są dołączane do repozytorium.

Połączenie z kodem GPL oznacza, że wynikowy program Sector Copy U1 jest
udostępniany na warunkach GPL-2.0-or-later. Pełny tekst znajduje się w
głównym pliku `LICENSE`.
