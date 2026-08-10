# Plan prób sprzętowych — wersja 0.6.8

Wszystkie próby zapisu wykonujemy wyłącznie na opisanych dyskietkach roboczych.
Najpierw powstaje znany obraz testowy z sumami kontrolnymi, potem kopia jest
ponownie zgrywana do ATR i porównywana na Macu.

## Próby wykonane na rzeczywistym sprzęcie

Kolejne wersje Sector Copy U1 były testowane na prawdziwym Atari 130XE z
Ultimate 1MB i rozszerzeniem Stereo oraz stacją Zaxona wyposażoną w ROM
HyperXF Stefana Dorndorfa. W obu kierunkach — ze stacji HyperXF oraz na stację
HyperXF — poprawnie wykonano kopie nośników:

- SD 90 KB;
- DD 180 KB;
- DD 720 KB na dyskietce 3,5 cala.

Potwierdza to praktyczne działanie wykrywania geometrii oraz odczytu i zapisu
z HyperXF dla skrajnego formatu 720 KB, którego pełna kopia obejmuje 2880
sektorów. Poniższy plan pozostaje matrycą dalszych regresji, urządzeń i prób
błędów, a nie listą samych testów emulatorowych.

## Kolejność

1. Atari800: pięć podstawowych formatów — SD 90 KB, ED 130 KB, DD 180 KB,
   dwustronny DD 360 KB i HyperXF DD 720 KB. Rzadkie kombinacje HyperXF są
   osobną próbą rozszerzoną, a nie dodatkowymi gęstościami.
2. Atari800: start bez DOS-u, pełne przejęcie spod DOS-u i zachowanie DOS-u.
3. FujiNet lub SIO2SD jako źródło, fizyczna stacja jako cel.
4. Fizyczna stacja jako źródło, FujiNet lub SIO2SD jako cel.
5. Dwie różne stacje fizyczne.
6. Jedna stacja z wymianą dyskietki po każdym przebiegu.
7. Próby błędów: write protect, brak dysku, wyjęcie dysku, zły format celu,
   cel o innej geometrii i kontrolowany uszkodzony sektor.
8. Oba warianty celu: domyślne `FORMAT: JAK ZRODLO` oraz `FORMAT: NIE`.
9. Ten sam szybki napęd przy zwykłym Atari OS, QMEG i BIOS-ie Ultimate 1MB:
   profil oraz czas kopii powinny pozostać takie same, bo program używa własnego
   sterownika POKEY.
10. Interfejs: klawisze `Z/C/K/F/W/S/T/P/Q`, potwierdzenia `START`/`SELECT`,
    czyste ekrany komunikatów i wszystkie cztery palety etapów.
11. Po kopii jednoprzebiegowej co najmniej dwie kolejne dyskietki zapisane z
    tego samego bufora; po kopii wieloprzebiegowej brak tej opcji.

## Matryca urządzeń

| Urządzenie | Profil oczekiwany | Formaty próbne |
|---|---|---|
| Zaxon XF551 clone, HyperXF Stefana Dorndorfa | `HXF`, zwykle `HXF9`; podczas transferu `FAST` | przede wszystkim 90, 130, 180, 360 i 720 KB; opcjonalnie rzadkie kombinacje HyperXF |
| Zaxon XF551 clone, ROM standardowy | XF551 High Speed, dzielnik 16 | 180 i 360 KB |
| CA2001 z Tygrys Turbo | UltraSpeed/Tygrys, zwykle dzielnik 10 | SD, ED i DD |
| Atari 1050 z rozszerzeniem turbo | profil zależny od rozszerzenia | SD, ED i DD |
| FujiNet | UltraSpeed według konfiguracji | wszystkie obrazy logiczne |
| SIO2SD | UltraSpeed według firmware | SD, ED, DD i obrazy rozszerzone |
| AVG Cart z SIO | według firmware | źródło i cel |
| SIO2PC | szybkość ustawiona po stronie serwera | źródło i cel |

Menu pokazuje rodzinę protokołu i efektywny dzielnik, np. `US10`, `XFHS16`,
`TURBO6` albo `WARP16`. HyperXF jest wyjątkiem: sygnatura STATUS `$D9` pozwala
pokazać własne oznaczenie `HXF`, np. `HXF9`; `HXF40` oznacza rozpoznaną stację
pracującą standardowo. Podczas kopiowania żywy napis `FAST`/`STD` opisuje
rzeczywisty tryb ostatniej operacji i może ujawnić fallback niewidoczny w
zapamiętanej nazwie profilu.

## Kryteria zaliczenia

- geometria zgłoszona przez program jest zgodna z nośnikiem;
- klawisze `Z` i `C` przechodzą tylko po stacjach oznaczonych podczas skanu
  jako obecne; przy jednej stacji oba panele pokazują ten sam numer;
- liczba sektorów i bajtów odpowiada obrazowi wzorcowemu;
- format i zapis kończą się statusem SIO `$01`;
- klawisze `Z/C/K/F/W/S/T/P/Q` działają bez `RETURN`, a ich pierwsze litery są
  pokazane w inverse;
- na każdym ekranie potwierdzenia `START` kontynuuje, a `SELECT` anuluje lub
  wraca; przytrzymany klawisz nie zatwierdza automatycznie następnego ekranu;
- ekran błędu lub sukcesu nie znika od klawisza pozostałego po poprzedniej
  operacji i pozostaje widoczny do następnego świadomego naciśnięcia;
- po błędzie celu, formatu, zapisu lub weryfikacji opcja `R` ponawia zapis
  bieżącej porcji z bufora bez ponownego uruchamiania odczytu źródła, a `F`
  ponawia formatowanie i zapis;
- weryfikacja programu nie zgłasza różnicy;
- ATR odczytany po próbie ma identyczne dane sektorów jak wzorzec;
- podczas każdego transferu numer sektora `$hhhh` odpowiada faktycznej operacji,
  a wyśrodkowana siatka ATASCII, łącznie z semigrafiką i inwersją, zmienia się
  zgodnie z danymi bieżącego sektora;
- ekran odczytu jest zielony, formatowania i zapisu czerwony, weryfikacji żółty,
  a menu, pytania, sukces i błędy wracają do granatu;
- podczas odczytu, zapisu i weryfikacji wskaźnik `FAST`/`STD` odpowiada trybowi
  faktycznie użytemu przez ostatnią komendę, także po retry i fallbacku;
- pełna 40-kolumnowa ramka, separator ATASCII i dolna krawędź pozostają
  nienaruszone na każdym ekranie;
- pierwszy pasek ma inverse `S`, wykorzystuje wszystkie 32 pola i zeruje się
  po 18 sektorach SD/DD albo 26 sektorach MD; drugi ma inverse `D` i rośnie
  przez całą dyskietkę; żaden z nich nie nadpisuje wiersza dolnej ramki;
- sektory 128/256/512 bajtów zajmują odpowiednio 4/8/16 wierszy podglądu;
- kopia większa od bufora przechodzi przez wszystkie zakresy bez pominięcia
  ani powtórzenia sektora;
- po udanej kopii jednoprzebiegowej `START` zapisuje następną dyskietkę z
  kompletnego bufora bez ponownego odczytu źródła, `SELECT` wraca do menu,
  a po kopii wieloprzebiegowej program nie proponuje zapisu z bufora;
- po błędzie turbo własny sterownik ponawia transfer bez zawieszenia;
- przy HyperXF panel pokazuje `HXF` i dzielnik, zwykle `HXF9`, a podczas
  rzeczywiście szybkich sektorów wskaźnik pokazuje `FAST`; czas kopiowania jest
  wyraźnie krótszy od wersji 0.4.4 używającej zwykłego SIOV;
- w trybie pełnym `Q`/`ESC` wykonuje zimny restart;
- w trybie zachowania `Q`/`ESC` wraca do DOS-u, a podstawowe polecenia DOS-u
  nadal działają.

## Szczególnie ważne dla HyperXF 720 KB

- PERCOM: 80 ścieżek, 2 strony, 18 sektorów na ścieżkę, 256 bajtów;
- 2880 sektorów logicznych;
- sektory 1-3 przesyłane po 128 bajtów;
- 736896 bajtów danych i 45 banków bufora;
- jeden przebieg na Ultimate 1MB oraz kontrolna próba wieloprzebiegowa z
  ograniczonym buforem;
- próba formatowania przez własny sterownik programu w trybie `FAST` oraz
  kontrola nośnika wcześniej sformatowanego narzędziem HyperXF/SpartaDOS X;
- porównanie kopii przy źródle i celu zamienionych między D1: i D2:;
- po szybkim formatowaniu komunikat `HYPERXF SKEW: ULTRASPEED`; komunikat
  `STANDARD` wymaga sprawdzenia, dlaczego komenda formatująca użyła fallbacku;
- obowiązkowa regresja pełnej geometrii: ATR `$0B40` → HyperXF → ponowny odczyt
  tej HyperXF nadal obejmuje `$0B40` sektorów.

## Pięć formatów podstawowych i próby rozszerzone HyperXF

Pierwsze, oznaczone pogrubieniem wiersze tworzą właściwą matrycę odbiorczą.
Pozostałe cztery wynikają z łączenia gęstości SD/MD z dodatkowymi stronami i
ścieżkami, które dopuszcza HyperXF; są użyteczne do kontroli ogólności kodu,
ale nie są typowymi formatami oprogramowania Atari. Każdy wybrany wiersz można
sprawdzić w obu kierunkach: ATR → fizyczna dyskietka po formatowaniu oraz
fizyczna dyskietka → nowy ATR. `KONIEC` jest ostatnim numerem sektora na
ekranie kopiowania.

| Nośnik | Gęstość | Geometria | Sektory × bajty | KONIEC |
|---|---|---:|---:|---:|
| **40T/1S, 90 KB** | **SD** | **40×1×18** | **720×128** | **`$02D0`** |
| **40T/1S, 130 KB** | **MD/ED** | **40×1×26** | **1040×128** | **`$0410`** |
| **40T/1S, 180 KB** | **DD** | **40×1×18** | **720×256** | **`$02D0`** |
| pełny 5,25 cala, 180 KB | SD | 40×2×18 | 1440×128 | `$05A0` |
| pełny 5,25 cala, 260 KB | MD | 40×2×26 | 2080×128 | `$0820` |
| **pełny 5,25 cala, 360 KB** | **DD** | **40×2×18** | **1440×256** | **`$05A0`** |
| pełny 3,5 cala, 360 KB | SD | 80×2×18 | 2880×128 | `$0B40` |
| pełny 3,5 cala, 520 KB | MD | 80×2×26 | 4160×128 | `$1040` |
| **pełny 3,5 cala, 720 KB** | **DD** | **80×2×18** | **2880×256** | **`$0B40`** |

W trybach HyperXF `A/B/C/D` oczekiwany jest wyłącznie widok 40T/1S. W trybach
`X`, `S`, `M` i `F` program może ogłosić większą geometrię dopiero po
potwierdzeniu kompletnych nagłówków na obu końcach każdego zakresu ścieżek.
Sprzeczny lub częściowy zestaw nie może zostać automatycznie zmniejszony i
użyty jako źródło, ponieważ groziłoby to cichym pominięciem danych.

## Próba rozpoznania HyperXF krok po kroku

1. Uruchomić 0.6.8 i poczekać na skan.
2. W panelu stacji Zaxona odczytać wiersz `SIO`. Dla ROM-u Stefana Dorndorfa
   oczekujemy `HXF9` albo `HXF` z innym dzielnikiem zwróconym przez `$3F`;
   `HXF40` oznacza, że stacja została rozpoznana, ale profil jest standardowy.
3. Wykonać najpierw `T`, potem kopię krótkiej dyskietki roboczej bez ważnych
   danych. Zanotować czas odczytu i zapisu osobno oraz obserwować żywy wskaźnik
   `FAST`/`STD` przy kolejnych sektorach.
4. Powtórzyć po zimnym starcie ze zwykłym Atari OS oraz QMEG. Wynik powinien
   być taki sam, ponieważ wersja 0.6.8 nie korzysta z SIOV ROM-u.
5. Sformatować cel w programie. Przy aktywnym szybkim profilu ekran powinien
   pokazać `HYPERXF SKEW: ULTRASPEED`; następnie zapis i żółta weryfikacja mają
   utrzymywać odpowiednio `FAST` albo jawnie pokazać chwilowy `STD` po fallbacku.
6. Jeżeli pojawi się błąd, sfotografować cały ekran z numerem sektora i kodem
   SIO oraz podać dokładny napis profilu z panelu. Dane odczytane do bufora
   pozostają dostępne do opcji `R`/`F` ponawiającej zapis.

## Regresja pełnego HyperXF 720 KB: `$0B40` → `$0B40`

Ta próba zabezpiecza błąd, w którym zapis pełnych 2880 sektorów kończył się
poprawnie, lecz późniejsze użycie fizycznej HyperXF jako źródła było skracane
do 720 sektorów przez zwrotny blok GET PERCOM.

1. Zamontować pełny wzorcowy ATR 720 KB jako źródło. Na ekranie kopiowania
   końcowym numerem ma być `$0B40` (2880 sektorów).
2. Włożyć roboczą dyskietkę do HyperXF, pozostawić `FORMAT: JAK ZRODLO` i
   uruchomić kopiowanie klawiszem `K`, zatwierdzając kolejne kroki `START`.
3. Podczas formatowania sprawdzić komunikat `HYPERXF SKEW: ULTRASPEED`, podczas
   zapisu `FAST`, a podczas weryfikacji żółty ekran i żywy `FAST`/`STD`.
4. Po sukcesie wrócić `SELECT` do menu, wykonać ponowny skan `S` i wybrać
   zapisaną HyperXF jako źródło klawiszem `Z`.
5. Rozpocząć nową kopię z HyperXF do pustego ATR 720 KB. Program musi ponownie
   wyznaczyć pełną geometrię; zakres odczytu ma kończyć się na `$0B40`, nie na
   `$02D0`.
6. Zgrać wynikowy ATR na Maca i porównać wszystkie sektory oraz SHA-256 z
   obrazem wzorcowym. Zaliczenie wymaga jednocześnie zakresu `$0B40`, poprawnej
   weryfikacji w programie i identycznych danych.

## Ograniczenie Atari800

Próba `-nopatch` potwierdza, że ramki przechodzą przez kod POKEY programu.
Atari800 7.1.1 potrafi podczas wykrywania zachować się jak 1050 Turbo, ale przy
właściwym odczycie nie interpretuje bitu Turbo w `DAUX2` jak prawdziwa stacja.
Dlatego pełny test emulatorowy wykonujemy z profilem standardowym wymuszonym w
tabeli debuggera; prędkość HyperXF musi zostać potwierdzona na sprzęcie.
