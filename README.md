# Sector Copy U1

Sector Copy U1 jest uniwersalnym, sektorowym kopierem całych dyskietek dla
8-bitowych komputerów Atari XL/XE. Obsługuje stacje D1:–D8:, standardowe
formaty od 90 do 720 KB, szybkie odmiany SIO, formatowanie celu, weryfikację
kopii oraz buforowanie w pamięci podstawowej i rozszerzonej — w tym Ultimate
1MB. Nie kopiuje plików i nie interpretuje katalogu ani systemu plików:
odczytuje po kolei wszystkie logiczne sektory źródła i odtwarza je na nośniku
docelowym.

Program jest samodzielnym plikiem XEX/COM. Można go uruchomić z prostego
loadera XEX albo spod DOS-u. Uruchomiony samodzielnie przejmuje komputer.
Po wykryciu DOS-u pozwala wybrać pełne przejęcie pamięci albo zachowanie DOS-u
i bezpieczny powrót po zakończeniu.

Nie jest to kopier fizyczny ani strumieniowy. Korzysta z komend sektorowych
udostępnianych przez stację poprzez Atari SIO, dlatego nie odtworzy ochron
opartych na słabych lub celowo błędnych sektorach, nietypowych identyfikatorach
albo surowym układzie ścieżki. Kopiuje natomiast całą logiczną zawartość
każdego prawidłowo rozpoznanego formatu obsługiwanego przez program i stację.

## Jak działa program

1. Skanuje D1:–D8: i pozwala wybrać tylko stacje, które odpowiedziały.
2. Dla źródła odczytuje sektor 1, STATUS i PERCOM, negocjuje szybkie SIO,
   a w HyperXF dodatkowo sprawdza rzeczywistą liczbę ścieżek. Na tej podstawie
   ustala rozmiar sektora, liczbę sektorów, gęstość i geometrię nośnika.
3. Oblicza dostępną pojemność bufora. W trybie pełnym wykrywa fizyczne banki
   PORTB i wykorzystuje także pamięć rozszerzoną; w trybie zachowania DOS-u
   ogranicza się do bezpiecznego okna 16 KB pamięci głównej.
4. Czyta kolejne sektory do bufora. Jeżeli mieści się w nim cały obraz,
   odczyt źródła odbywa się jednym przebiegiem; w przeciwnym razie program
   automatycznie dzieli kopię na przebiegi zawierające pełne sektory.
5. Po zakończeniu odczytu może sformatować dysk docelowy zgodnie z geometrią
   źródła albo zachować istniejący format po sprawdzeniu jego zgodności.
6. Zapisuje sektory na cel komendą SIO z weryfikacją wykonywaną przez stację.
   Opcjonalnie ponownie odczytuje całą kopię i porównuje każdy bajt z buforem.
7. Po błędzie celu zachowuje dane bieżącego przebiegu, aby można było ponowić
   formatowanie lub zapis. Po udanej kopii jednoprzebiegowej pozwala nagrać
   z tego samego bufora następne dyskietki bez ponownego czytania źródła.

Podczas odczytu, zapisu i weryfikacji program pokazuje numer sektora, jego
zawartość jako pełny zestaw znaków ATASCII, faktycznie używaną prędkość SIO
oraz osobne paski postępu bieżącej ścieżki i całej dyskietki.

## Autorstwo i wykorzystane procedury

Kod interfejsu, wykrywania pamięci, bankowanego bufora, rozpoznawania geometrii
(łącznie z obsługą HyperXF), logiki formatowania, kopiowania, ponowień i
weryfikacji został opracowany specjalnie dla Sector Copy U1. Wygląd ekranu
sektora jest inspirowany sposobem prezentacji znanym z kopiera QMEG, ale projekt
nie zawiera kodu QMEG ani kodu innych dawnych kopierów.

Jedynym włączonym do pliku wynikowego zewnętrznym modułem programowym jest
**Highspeed SIO 1.33** autorstwa Matthiasa Reichla (HiassofT), Copyright
© 2003–2023. Moduł obsługuje transmisję przez POKEY oraz negocjację rodzin
UltraSpeed, 1050 Turbo, XF551 High Speed i Happy 810 Warp. W projekcie użyto
oryginalnego wydania 1.33 z ustawieniami `FASTVBI`, `MAXDRIVENO=8` i adresem
`START=$3985`; kod integrujący go z kopierem oraz dodatkowe rozpoznawanie
HyperXF należą do Sector Copy U1.

Komplet niezmienionych źródeł wydania 1.33 i jego oryginalna licencja znajdują
się w [`third_party/highspeed-sio-1.33`](third_party/highspeed-sio-1.33).
Dokładny sposób zbudowania użytego obrazu, suma kontrolna i pochodzenie wersji
są opisane w [`docs/THIRD_PARTY.md`](docs/THIRD_PARTY.md). Highspeed SIO jest
udostępniany na warunkach GPL-2.0-or-later, dlatego cały połączony program
Sector Copy U1 jest publikowany na tych samych warunkach.

## Stan projektu: 0.6.6

Aktualna wersja zawiera:

- wariant B menu: dwa symetryczne panele `ZRODLO` i `CEL`, wyraźne pole
  kopiowania oraz oddzielna, uporządkowana sekcja ustawień; litery skrótów
  `Z/C/K/F/W/S/T/P/Q` są pokazane w inverse;
- opisowy wariant A informacji o nośniku: numer stacji i pojemność, pełna
  nazwa gęstości, geometria, liczba sektorów oraz protokół SIO w osobnych
  wierszach obu paneli;
- pełnoekranowy interfejs E: wykorzystujący wszystkie 40 kolumn: semigraficzna
  ramka zajmuje kolumny 0 i 39, a tekst kolumny 1-38;
- cztery palety etapów o wysokim kontraście: granatowe menu i komunikaty,
  zielony odczyt, czerwony format i zapis oraz żółta weryfikacja;
- natychmiastowy odczyt pojedynczych klawiszy przez osobne urządzenie `K:`;
- potwierdzanie operacji fizycznymi klawiszami konsoli: `START` kontynuuje,
  a `SELECT` anuluje lub wraca do menu;
- stockowy, wycentrowany glif pionowej krawędzi, poprawny również na pierwszym
  ekranie wyboru trybu i w trybie zachowania DOS-u;
- inspirowany kopierem QMEG-a ekran bieżącego sektora: wyśrodkowana siatka
  pełnego ATASCII, numer szesnastkowy, odwrócony pasek etapu oraz dwa paski:
  bieżącej ścieżki i całej dyskietki, odświeżane po każdym sektorze;
- osobne, czyste ekrany wszystkich próśb o włożenie lub sprawdzenie nośnika;
- skan D1:-D8: oraz wybór źródła i celu wyłącznie spośród stacji, które
  odpowiedziały; jedna stacja pozostaje poprawnym źródłem i celem;
- STATUS, PERCOM i aktywne rozpoznawanie protokołów szybkiego SIO;
- wbudowany sterownik POKEY Highspeed SIO 1.33 Matthiasa Reichla dla
  UltraSpeed, 1050 Turbo, XF551 High Speed i Happy Warp, niezależny od ROM-u
  systemowego i DOS-u;
- rozpoznawanie trzech gęstości zapisu: SD, MD/ED i DD oraz pięciu typowych
  formatów Atari 90/130/180/360/720 KB; uogólniony detektor rozumie również
  rzadkie kombinacje geometrii dopuszczone przez HyperXF, ale nie przedstawia
  ich jako odrębnych „gęstości”; HyperXF jest identyfikowana własnym
  oznaczeniem `HXF`, np. `TURBO HXF9`, niezależnie od rodziny negocjowanego
  protokołu;
- żywy wskaźnik `FAST`/`STD` na ekranie sektora, pokazujący tryb faktycznie
  użyty przez ostatnią operację, także po automatycznym fallbacku sterownika;
- bufor strumieniowy w oknie `$4000-$7FFF`, przekraczający granice banków;
- własne, destrukcyjne wykrywanie fizycznych banków przez PORTB, niezależne od
  DOS-u i jego tablic pamięci;
- obsługę 130XE, rozszerzeń zgodnych z typowymi układami PORTB oraz 1088K
  Ultimate 1MB;
- wykorzystanie 64 banków rozszerzonych i głównego okna 16 KB na U1MB;
- wybór przy starcie spod DOS-u: pełne przejęcie albo pozostawienie DOS-u;
- w trybie pełnym usunięcie rezydentnego DOS-u z `$0700-$36FF`, odłączenie
  pozostawionego PBI i przywrócenie bezpiecznych wektorów VBI;
- w trybie zachowania DOS-u użycie tylko głównego okna 16 KB, bez badania
  pamięci rozszerzonej;
- wyliczanie potrzebnej pamięci z faktycznej geometrii;
- automatyczny podział kopii na przebiegi mieszczące pełne sektory, gdy bufor
  jest mniejszy od dyskietki;
- pełny odczyt źródła, opcjonalne formatowanie celu, zapis i porównanie
  wszystkich bajtów;
- trzy próby każdego odczytu i zapisu;
- zapis komendą `$57`, czyli z dodatkową weryfikacją wykonywaną przez stację;
- opcjonalną końcową weryfikację całej kopii;
- ponowny zapis bieżącej porcji bez ponownego czytania źródła po błędzie celu,
  formatowania, zapisu albo weryfikacji;
- zapis następnych dyskietek docelowych z zachowanego bufora po udanej kopii
  jednoprzebiegowej, bez ponownego odczytu źródła;
- automatyczny wybór przeplotu HyperXF Ultra-Speed podczas formatowania, gdy
  komenda formatowania została rzeczywiście przesłana szybko;
- dwa potwierdzenia `START` przed pierwszym zapisem na nośnik docelowy.

Dysk HyperXF 720 KB ma 2880 sektorów po 256 bajtów, przy czym trzy sektory
startowe są przesyłane po 128 bajtów. Cały obraz zajmuje 736896 bajtów, czyli
45 okien po 16 KB. U1MB mieści go w jednym przebiegu; mniejsza pamięć powoduje
automatyczny podział na kilka przebiegów.

## Uruchomienie i pamięć

Plik wynikowy nie wymaga SpartaDOS X ani konkretnego DOS-u. Samodzielny start
z loadera XEX od razu wybiera tryb pełny. Po uruchomieniu spod DOS-u pojawia
się wybór:

1. **Pełny — odłącz DOS.** Program porzuca stos wywołujący, czyści obszar
   DOS-u, bada banki PORTB i używa całej wykrytej pamięci. `Q`/`ESC` wykonuje
   zimny restart.
2. **Zachowaj DOS.** Program nie bada banków rozszerzonych i wykorzystuje
   wyłącznie główne `$4000-$7FFF`. `Q`/`ESC` odtwarza `PORTB`, `APPMHI` oraz
   używaną stronę zerową, po czym wraca przez `RTS` do DOS-u.

Tryb zachowania DOS-u jest dostępny, gdy `MEMLO` nie przekracza `$3600`.
Jeśli DOS zajmuje więcej pamięci głównej, program proponuje powrót albo pełne
przejęcie. Obsługa RAM-dysków nie jest na tym etapie wykonywana.

Obszar `$3600-$37FF` pozostaje zarezerwowany na teksty interfejsu i pomocniczy
kod pasków. Stały stan zaczyna się od `$3800`, sterownik
HSIO 1.33 zajmuje `$3985-$3D09`, małe procedury interfejsu `$3D0A-$3DFF`,
a jeden wspólny sektor roboczy 512 bajtów `$3E00-$3FFF`. Kod i teksty zaczynają
się od `$8000`.
Weryfikacja porównuje dane celu bezpośrednio z bieżącym bankiem, dlatego drugi
bufor sektorowy nie jest potrzebny. Przed otwarciem ekranu ustawiane jest
`APPMHI`, aby standardowy handler `E:` nie umieścił ekranu lub display listy
na programie. Zakres `$4000-$7FFF` pozostaje wyłącznie oknem bufora bankowanego.

## Wizualizacja sektorów

Podczas odczytu, zapisu i końcowej weryfikacji ekran pokazuje:

- wyśrodkowane `SEKTOR $hhhh / $hhhh`;
- odwrócony pasek aktualnego etapu: odczyt, zapis albo weryfikacja;
- wyśrodkowane 4, 8 albo 16 wierszy po 32 znaki dla sektorów 128, 256 albo
  512 bajtów;
- wszystkie 256 wartości bajtu przeliczone na właściwe kody ekranowe ATASCII,
  łącznie ze znakami sterującymi, semigrafiką i inwersją;
- pasek `S`, który skaluje 18 sektorów SD/DD albo 26 sektorów MD na pełne
  32 pola, dochodzi do prawego końca wraz z ostatnim sektorem ścieżki i wtedy
  zeruje się dla następnej;
- pasek `D`, który narasta przez wszystkie sektory całej dyskietki i zachowuje
  właściwą pozycję między porcjami bufora.

Podgląd jest zapisywany bezpośrednio do pamięci standardowego ekranu GR.0,
dzięki czemu aktualizacja po każdym sektorze nie wymaga setek osobnych wywołań
CIO. Krótsze sektory nie są otoczone polem sztucznych kropek: 128 bajtów
zajmuje centralne 4×32 znaki, 256 bajtów 8×32, a 512 bajtów 16×32. Program
ustawia `LMARGN=1` i `RMARGN=38`, usuwa więc standardowy lewy margines dwóch
kolumn i pozostawia skrajne kolumny na ramkę. W trybie zachowania DOS-u
poprzednie marginesy, kolory i stan kursora są odtwarzane.

## Szybkie SIO

Wersja 0.6.6 nie wywołuje systemowego `SIOV` dla operacji stacji. Każdy
STATUS, PERCOM, sektor i format przechodzi przez niezależny sterownik POKEY
Highspeed SIO 1.33 Matthiasa Reichla (HiassofT). Dzięki temu wynik nie zależy od
tego, czy komputer ma zwykły OS, QMEG, BIOS Ultimate 1MB albo szybki sterownik
załadowany przez SpartaDOS X.

Przy pierwszej komendzie do każdej Dn: sterownik wykonuje kolejno:

1. standardowe zapytanie UltraSpeed `$3F` i odczyt dzielnika POKEY;
2. próbę STATUS w protokole 1050 Turbo;
3. próbę STATUS w protokole XF551 High Speed;
4. próbę Happy 810 Warp;
5. zapis profilu standardowego, jeśli żaden tryb szybki nie odpowiedział.

Kolejne operacje korzystają z zapamiętanego profilu. UltraSpeed wysyła całą
ramkę szybko, 1050 Turbo ustawia bit 7 `DAUX2`, XF551 bit 7 rozkazu, a Happy
Warp bit 5 rozkazu. Sterownik ma własne ponowienia i drugą serię prób w
standardowej prędkości po błędzie szybkiej transmisji.

HyperXF Stefana Dorndorfa jest rozpoznawana po własnej sygnaturze STATUS `$D9`.
Panel pokazuje `HXF` wraz z zapamiętanym dzielnikiem, np. `TURBO HXF9`;
`TURBO HXF40`
oznacza rozpoznaną HyperXF z wynegocjowanym profilem standardowym. Pozostałe
urządzenia UltraSpeed nadal są opisywane jako `US<n>`.
Sama nazwa profilu nie dowodzi, że każda operacja przeszła szybko, dlatego
podczas transferu obok numeru sektora działa wskaźnik `FAST`/`STD`. Jest on
aktualizowany po każdym rozkazie z rzeczywistej wartości użytej przez
sterownik i ujawnia automatyczny fallback do prędkości standardowej.

W przypadku HyperXF program nie ufa zwrotnemu GET PERCOM jako opisowi aktualnej
dyskietki: firmware może zwracać ostatni blok ustawiony przez SET PERCOM.
Zgodnie z klasyczną praktyką DOS-ów program najpierw czyta sektor 1, następnie
odczytuje STATUS i dodatkowo wymusza sprawdzenie gęstości przez STATUS z
`AUX2='U'`. Potem bada komendą GET TRACK INFO `$67` rzeczywiste ścieżki
graniczne 0/39/40/79
oraz — dla mechanizmu 3,5 cala — 80/159. Nie uznaje samego powodzenia komendy:
parsuje tablicę nagłówków, pomija prawidłowe wpisy przerw `$C0` i wymaga
dokładnie jednego kompletu sektorów 1-18 albo 1-26, bez duplikatów i kodów
błędów. W ten sposób rozróżnia wszystkie
standardowe geometrie 40T/1S, 40T/2S i 80T/2S bez obcinania pełnego nośnika
720 KB do 720 sektorów. Jeśli ślady są częściowe lub sprzeczne, stacja nadal
jest widoczna, lecz nośnik nie może zostać użyty jako źródło o zgadywanym
rozmiarze. Pięć podstawowych wyników to 90 KB SD, 130 KB MD/ED, 180 KB DD,
360 KB dwustronne DD i 720 KB DD na 3,5 cala. Krytyczna regresja sprzętowa ma
postać: źródłowy ATR `$0B40`
sektorów → sformatowana i zapisana HyperXF → ponowny odczyt HyperXF nadal
`$0B40`.

Podczas formatowania rozpoznanej HyperXF szybkość samej komendy `$21`/`$22`
wybiera po stronie firmware przeplot sektorów. Program korzysta z tego
automatycznie i po operacji pokazuje `HYPERXF SKEW: ULTRASPEED` albo
`HYPERXF SKEW: STANDARD`, zgodnie z trybem faktycznie użytym po retry.

Obecna warstwa obejmuje cztery szerokie rodziny zgodne z implementacją
HiassofT: UltraSpeed, 1050 Turbo, XF551 i Happy Warp. Nietypowe odmiany TOMS lub
Top Drive korzystające z własnych komend ładowanych do RAM stacji będą wymagały
osobnego rozpoznania i prób z konkretnym ROM-em; nie są jeszcze deklarowane jako
gotowe.

## Bezpieczny przebieg kopiowania

1. `K` sprawdza źródło, cel, geometrię i pojemność bufora.
2. `START` rozpoczyna wyłącznie odczyt źródła; `SELECT` anuluje.
3. Po odczycie program prosi o włożenie lub sprawdzenie dysku docelowego.
4. `START` uruchamia domyślnie formatowanie celu według geometrii źródła,
   a następnie zapis; `SELECT` wraca bez zapisu. Jeśli w menu ustawiono
   `FORMAT: NIE`, program pomija formatowanie i sprawdza geometrię istniejącego
   nośnika.
5. Jeśli włączono weryfikację, program ponownie czyta cel i porównuje każdy
   bajt z buforem źródłowym.
6. Jeśli potrzebny jest kolejny przebieg, dwie różne stacje przechodzą do niego
   automatycznie. Przy jednej stacji program prosi o każdą wymianę dyskietki.

Po udanej kopii jednoprzebiegowej cały obraz nadal znajduje się w pamięci.
Ekran sukcesu pozwala włożyć następną dyskietkę: `START` formatuje lub sprawdza
nowy cel i zapisuje go bez ponownego odczytu źródła, a `SELECT` wraca do menu.
Opcja nie jest pokazywana po kopii wieloprzebiegowej, ponieważ bufor zawiera
wtedy tylko ostatnią porcję, a nie całą dyskietkę.

Po błędzie dotyczącym celu dane bieżącej porcji pozostają w pamięci. `R` ponawia
zapis bez ponownego odczytu źródła, `F` ponownie formatuje cel i zapisuje dane,
a `Q`/`ESC` świadomie rezygnuje. Ponowienie zaczyna zapis porcji od jej
pierwszego sektora, dzięki czemu częściowo zapisany nośnik jest odtwarzany
spójnie.

Formatowanie używa bloku PERCOM źródła. Dla gęstości rozszerzonej stosowana
jest komenda `$22`, a dla pozostałych formatów `$21`. Każda nowa dyskietka
docelowa jest formatowana tylko przed swoim pierwszym przebiegiem. Po poprawnie
zakończonych `SET PERCOM` i `FORMAT` program rozpoczyna zapis także wtedy, gdy
urządzenie docelowe nie potrafi odczytać zwrotnie swojej nowej geometrii przez
PERCOM. Przy ustawieniu `FORMAT: NIE` zgodność geometrii nadal jest obowiązkowo
sprawdzana.

## Klawisze

Wszystkie pozycje głównego menu reagują natychmiast na pojedyncze naciśnięcie
klawisza — nie wymagają `RETURN`. Pierwsze litery poleceń są pokazane w
inverse. Wyjście klawiatury `K:` jest oddzielone od ekranowego `E:`, dlatego po
klawiszu nie pozostaje w buforze znak końca wiersza. Małe i wielkie litery są
traktowane tak samo.

- `Z` — następna wykryta stacja źródłowa;
- `C` — następna wykryta stacja docelowa;
- `K` — kopiowanie;
- `F` — przełączenie `FORMAT: JAK ZRODLO` / `FORMAT: NIE`;
- `W` — włączenie lub wyłączenie końcowej weryfikacji;
- `S` — ponowny skan D1:-D8: i korekta nieaktualnych wyborów;
- `T` — bezpieczny test odczytu sektora 1;
- `P` — informacje o pamięci;
- `Q` lub `ESC` — powrót do DOS-u w trybie zachowania albo zimny restart
  w trybie pełnym.

Na ekranach potwierdzeń `START` oznacza kontynuację, a `SELECT` anulowanie lub
powrót. Program czeka najpierw na zwolnienie klawiszy konsoli, więc przytrzymany
`START` nie zatwierdzi automatycznie następnego ekranu.

## Budowanie na macOS

Potrzebne są:

- Homebrew;
- `cc65` (`ca65` i `ld65`);
- `make`;
- Atari800 do kontroli pliku XEX.

Do zwykłego budowania nie jest potrzebny ATASM, ponieważ sprawdzony obraz HSIO
jest dołączony w repozytorium. ATASM jest potrzebny tylko do jego regeneracji
z dołączonych, oryginalnych źródeł HiassofT.

Instalacja:

```sh
brew install cc65 atari800
```

Budowanie i testy:

```sh
make test
```

Wynik:

```text
build/sector-copy-u1.xex
```

Powtarzalne obrazy ATR do emulatora:

```sh
python3 tools/make_test_atr.py
```

Generator tworzy pary `source-*`/`target-*` dla SD, MD/ED, DD, XF551 360 KB
oraz wszystkich pełnych geometrii HyperXF 5,25 i 3,5 cala w katalogu
`test-disks`.

## Potwierdzone testy

- samodzielny start XEX po inicjalizacji Atari OS bez DOS-u;
- fizyczne wykrycie 65 okien bufora na emulowanym 1088XE;
- pełne kopiowanie SD 720 sektorów D1:→D2: z końcową weryfikacją;
- domyślne formatowanie celu przed zapisem i potwierdzanie klawiszem `START`;
- klawisze `Z/C/K/F/W/S/T/P/Q` działające bez `RETURN` przez handler `K:`;
- `START` i `SELECT` odczytywane bezpośrednio z klawiszy konsoli, z kontrolą
  ich wcześniejszego zwolnienia;
- co najmniej sekundowe wyświetlanie komunikatu formatowania oraz ekranów
  sukcesu, błędu i informacji przed przyjęciem kolejnego klawisza;
- odświeżanie numeru sektora w hex, pełnej siatki ATASCII i dolnego wskaźnika
  po każdym z 720 sektorów podczas odczytu, zapisu i weryfikacji;
- zielona paleta odczytu, czerwona paleta formatowania i zapisu, żółta paleta
  weryfikacji oraz powrót do granatowej palety na ekranach komunikatów;
- ponowna pełna kopia z jednoprzebiegowego bufora po `START`, bez wywołania
  odczytu źródła; przy wielu przebiegach opcja pozostaje niedostępna;
- wymuszony błąd po pierwszym zapisie, a następnie `R`: ponowny zapis i
  weryfikacja zakończone bez ponownego odczytu źródła; wynikowy ATR identyczny
  ze źródłem;
- kopia SD z DOS-em zachowanym, jednym buforem 16 KB i sześcioma automatycznymi
  przebiegami;
- powrót `RTS` do programu wywołującego z odtworzeniem `PORTB`, `APPMHI`
  i 16 bajtów używanej strony zerowej;
- start Atari800 z opcją `-nopatch`, czyli bez emulacyjnego przechwycenia
  systemowego SIOV; pełny odczyt, format i zapis przez własny sterownik POKEY;
- wymuszony standardowy profil w Atari800 (emulator nie realizuje w pełni
  protokołu 1050 Turbo): źródłowy i docelowy ATR po zapisie są identyczne,
  SHA-256 `8ed7b16a7431d76cce82803fba576c2ed104348872e9ece5e527debc4fbe4ae3`;
- aktywne wykrycie profilu 1050 Turbo w emulatorze i poprawna prezentacja
  `TURBO 1050/6` (wcześniejsze błędne `US128` zostało usunięte);
- wybór `Z`: D1:→D2:→D1: przy obecnych D1:/D2: i nieobecnych D3:–D8:;
- zewnętrzne porównanie obu ATR-ów: identyczne pliki i SHA-256
  `a059bfcb24abbd3738314baea12d8779df5f8b5e8b52df065dfb3bd6fb1a1074`.

## Ważne uwagi

- W trybie pełnym program przejmuje całą wykrytą pamięć rozszerzoną. Przed
  uruchomieniem należy zapisać pracę.
- W trybie zachowania DOS-u pamięć rozszerzona nie jest badana ani używana.
- Do kopii HyperXF 720 KB w jednym przebiegu potrzeba co najmniej 45 okien
  bufora. Ultimate 1MB w trybie 1088K udostępnia programowi 65.
- Wersja 0.6.6 wymaga prób na dyskietkach roboczych przed użyciem z ważnymi
  archiwami.
- Atari800 potrafi odpowiedzieć na rozpoznanie 1050 Turbo, lecz nie emuluje
  poprawnie dalszego numerowania sektorów z bitem Turbo. Nie zastępuje więc
  testu szybkiego transferu z prawdziwą stacją.
- Kopiowane są logiczne sektory. Program nie odtworzy słabych sektorów,
  niestandardowych identyfikatorów ani części zabezpieczeń opartych na surowej
  strukturze ścieżki.
- Obsługa 512-bajtowych sektorów jest obecna w silniku. Pełny nośnik 2880×512
  przekracza bufor U1MB i jest dzielony na dwa przebiegi.

Plan testów sprzętowych znajduje się w
[`docs/HARDWARE_TEST_PLAN.md`](docs/HARDWARE_TEST_PLAN.md).

Szczegóły protokołu i uzasadnienie wykrywania geometrii opisuje
[`docs/HYPERXF_GEOMETRY.md`](docs/HYPERXF_GEOMETRY.md).

Pochodzenie i sposób odtworzenia zewnętrznego sterownika opisuje
[`docs/THIRD_PARTY.md`](docs/THIRD_PARTY.md). Całość jest udostępniana na
warunkach GPL-2.0-or-later; zobacz [`LICENSE`](LICENSE).
