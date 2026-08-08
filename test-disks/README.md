# Obrazy ATR do testów

Pliki są generowane poleceniem:

```sh
python3 tools/make_test_atr.py
```

Każdy format ma parę:

- `source-*` — deterministyczny wzór danych, inny dla każdego sektora;
- `target-*` — wyzerowany obraz o tej samej geometrii.

Zestaw podstawowy obejmuje pięć praktycznych formatów Atari: 90, 130, 180,
360 i 720 KB. Dodatkowo generator tworzy rzadkie kombinacje geometrii opisane
przez protokół HyperXF, aby testować detektor niezależnie od typowości DOS-u:

- 5,25 cala: SD 1440×128, MD 2080×128 i typowe DD 1440×256;
- 3,5 cala: SD 2880×128, MD 4160×128 i typowe DD 2880×256;
- zgodnościową nazwę `hyperxf-2880` dla obrazu 720 KB używanego przez starsze
  próby regresji.

W obrazach z sektorami 256-bajtowymi pierwsze trzy sektory mają po 128 bajtów,
zgodnie z układem ATR i sposobem transmisji Atari.

Obrazy są wyłącznie nośnikami testowymi. Nie zawierają systemu plików ani DOS-u.
