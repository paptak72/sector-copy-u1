# Składniki zewnętrzne

## Highspeed SIO 1.33

Sector Copy U1 zawiera kod Highspeed SIO autorstwa Matthiasa Reichla
(HiassofT), Copyright © 2003–2023. Oryginalne źródła:

- <https://github.com/HiassofT/highspeed-sio>
- licencja: GNU General Public License, wersja 2 lub — według wyboru — dowolna
  późniejsza (`GPL-2.0-or-later`).

Do programu dołączony jest plik:

```text
src/hsio-1.33-3985-max8.bin
```

Parametry kompilacji różnią się od domyślnych wyłącznie konfiguracją miejsca
i liczby stacji:

```sh
atasm -dFASTVBI -dMAXDRIVENO=8 -dSTART=$3985 hisio.src
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

Połączenie z kodem GPL oznacza, że wynikowy program Sector Copy U1 jest
udostępniany na warunkach GPL-2.0-or-later. Pełny tekst znajduje się w
głównym pliku `LICENSE`.
