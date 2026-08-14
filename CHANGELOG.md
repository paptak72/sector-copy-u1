# Historia zmian

W tym pliku są opisane różnice między kolejnymi opublikowanymi wersjami
Sector Copy U1. Każda wersja ma własny tag i gotowy plik XEX w wydaniach
repozytorium GitHub.

## [0.6.9] - 2026-08-14

### Zmieniono

- Ekran główny otrzymał zatwierdzony wariant C3: jedną zewnętrzną ramę
  40×24, wspólny blok źródła i celu, wbudowaną sekcję kopiowania oraz
  uporządkowany blok ustawień.
- Zastosowano rzeczywiste połączenia semigraficzne ATASCII: rozgałęzienia,
  skrzyżowanie oraz górne i dolne zakończenie środkowego pionu. Linie paneli
  tworzą dzięki temu ciągłą konstrukcję zamiast niezależnych ozdobników.
- Informacje o obu stacjach zachowują dotychczasową zawartość: numer,
  pojemność, gęstość, geometrię, liczbę sektorów i wykryty protokół SIO.
- Uogólniono procedurę rysowania ramek. Ten sam kod obsługuje teraz pełną
  szerokość menu oraz węższe bloki ekranu `PARAMETRY KOPII`, nie zwiększając
  wymagań pamięciowych programu.
- Naprawiono właściwą przyczynę rozpoznawania DD jako ED w standardowym
  XF551. Firmware wyłącza sektory 1–3 z kontroli długości, dlatego po samym
  `READ 1` pozostaje w przejściowym ED. Dla rodziny XF program wykonuje teraz
  pojedynczy `READ 4/256`, czeka dziewięć ramek i dopiero drugi `STATUS`
  przyjmuje jako wynik wykrywania nośnika.
- Ograniczono sondę sektora 4 do stacji rozpoznanej przez timeout `$FE` albo
  profil XF551 High Speed. Dla pewnego XF sonda nie ufa pierwszym bitom
  gęstości, ponieważ po błędzie mogą opisywać stary nośnik. Pozostałe stacje
  zachowują zwykłą sekwencję `READ 1 → STATUS` i nie otrzymują obcego rozkazu.
- Poprawiono priorytet bitów pierwszego bajtu `STATUS`: bit 5, oznaczający
  sektor dłuższy niż 128 B, jest sprawdzany przed bitem 7 ED. Tak samo robią
  QMEG i Disk Communicator; MyDOS potwierdza pierwszeństwo bitu 5 przy wyborze
  długości sektora. Defensywnie obsługuje to też mieszaną odpowiedź `$A0`
  jako DD.
- `GET PERCOM` jest przyjmowany tylko wtedy, gdy jego klasa długości sektora
  nie przeczy końcowemu STATUS; dla sektorów 128-bajtowych sprawdzane jest też
  rozróżnienie 18/26 na ścieżkę. Stary profil ED nie może już nadpisać DD.
- Usunięto zawodną próbę rozróżniania 180/360 KB odczytem sektora `$05A0`.
  Stare dane na drugiej stronie mogą sprawić, że taki sektor istnieje również
  na dyskietce logicznie jednostronnej, co zostało potwierdzone na prawdziwym
  XF551. Dla standardowego XF551/DD program przyjmuje teraz domyślnie 40T/1S,
  720 sektorów i 180 KB.
- Dodano opcję `G — GEOMETRIA`. Jest dostępna dla niejednoznacznego DD
  rodziny XF551/HyperXF i świadomie przełącza źródło na 40T/2S,
  1440 sektorów i 360 KB. Zmiana źródła albo ponowny skan przywraca domyślne
  180 KB; wybrany wariant obowiązuje także kontrolę i formatowanie celu.
- HyperXF nie odrzuca już dyskietki 180 KB tylko dlatego, że na dalszej stronie
  odnalazła fragment starych nagłówków. Taki niejednoznaczny wynik przyjmuje
  bezpieczne 40T/1S i, tak jak standardowy XF551, pozwala użyć `G` dla 40T/2S.
- Zapis sektorów używa teraz PUT `$50` zamiast WRITE WITH VERIFY `$57`.
  Usuwa to podwójną weryfikację każdego sektora: przy `WERYFIKACJA: TAK`
  program nadal wykonuje silniejszy, pełny odczyt celu i porównanie z buforem.
- Dodano pomocniczy `xf551-density-diagnostic.xex`. Zatrzymany ekran pokazuje
  wyniki i rzeczywiste tryby SIO dla READ 1, pierwszego STATUS, READ 4,
  drugiego STATUS oraz wszystkie bajty PERCOM. Umożliwia sprawdzenie na
  sprzęcie oczekiwanej przemiany `$80 → $60` bez zgadywania na podstawie menu.
- Usunięto przycięcia transferu ze standardowym ROM-em XF551 ujawnione przez
  porównanie trzech nagrań tej samej dyskietki 180 KB. Odstępy numerów sektorów
  wykazały oczekiwanie o cały dodatkowy obrót nośnika, podczas gdy QMEG oraz
  HyperXF trafiały w kolejne okno przeplotu.
- Zwykłe READ/PUT ponownie używa scratch `$3E00-$3FFF`, a obowiązkowa pętla
  przesyłająca dane między scratch i bankiem jednocześnie tworzy surowy
  podgląd. Usunięto osobną konwersję 128–512 bajtów, ale dane nie są już
  rozlewane po pełnych 40-bajtowych wierszach ekranu.
- Podgląd sektora otrzymał wyśrodkowaną ramkę z wnętrzem szerokim na 32 znaki.
  Sektory 128/256/512 B zajmują dokładnie 4/8/16 wierszy, więc zawartość nie
  nadpisuje semigraficznych pionów ani zewnętrznej ramki ekranu.

### Do sprawdzenia

- Wygląd i działanie wszystkich skrótów nowego menu na prawdziwym Atari.
- Domyślne 180 KB oraz ręczny wybór 360 KB klawiszem `G` na stacji Zaxona ze
  standardowym ROM-em, łącznie z odczytem, formatowaniem, zapisem i weryfikacją.
- Równy rytm odczytu, zapisu i weryfikacji dyskietki DD na standardowym ROM-ie
  XF551 po połączeniu podglądu z transferem bankowym; porównać z QMEG i HyperXF.

### Sprawdzono na sprzęcie

- Diagnostyka na Atari 130XE i stacji Zaxona ze standardowym ROM-em potwierdziła
  dla dyskietki DD przejście `STATUS $80 → $60` po `READ 4/256`, poprawny
  odczyt PERCOM 40T/2S/18×256 oraz szybki profil XF551 `$40`.
- Ta sama próba wykazała, że bit dwóch stron i dostępny sektor `$05A0` nie
  rozstrzygają logicznego formatu: dyskietka 180 KB została przez firmware i
  dawną heurystykę błędnie pokazana jako 360 KB.
- Na Atari 130XE z Ultimate 1MB i Stereo oraz stacji Zaxona ze standardowym
  ROM-em XF551 sprawdzono wykrywanie, odczyt, formatowanie i zapis dyskietki
  180 KB DD. Po sformatowaniu przez kopier nośnik utrzymuje równy rytm
  szybkiego odczytu i zapisu.
- Tę samą dyskietkę 180 KB DD poprawnie skopiowano po przełączeniu stacji
  Zaxona na HyperXF.
- Na prawdziwym Atari potwierdzono poprawny wygląd wyśrodkowanego podglądu
  sektora: dane pozostają wewnątrz ramki 32-kolumnowej i nie nadpisują
  semigrafiki ekranu.

## [0.6.8] - 2026-08-10

### Zmieniono

- Kształt opisów klawiszy `START` i `SELECT` wykorzystuje poprawny znak
  ATASCII 8 oraz jego odmianę w negatywie 136 (`$88`).
- Przed otwarciem interfejsu kopier jawnie ustawia `PORTB=$FF`: wyłącza ROM
  BASIC-u i SELF TEST, wybiera podstawowy RAM dla CPU i ANTIC oraz pozostawia
  system operacyjny w ROM-ie.
- Tryb pełny nadal sonduje wszystkie 64 kombinacje selektora Ultimate 1MB.
  Bit sterujący BASIC-em może być chwilowo częścią numeru banku rozszerzonego,
  ale po każdym dostępie przywracany jest stan `$FF`, więc zmaksymalizowanie
  bufora nie pozostawia BASIC-u włączonego.
- Ekran `PAMIEC` nie pokazuje już nieprzydatnego pochodzenia uruchomienia
  `DOS / LOADER`. Zawiera jednoznaczną wartość `BUFOR RAZEM` w KB, obliczaną
  z mapy bufora rzeczywiście dostępnej w wybranym trybie pracy.
- Poprawiono układ ekranu wyboru trybu: separator nie przecina podpisu autora,
  a kolejne opcje są rozdzielone pustymi wierszami.
- Oddzielono przejście do separatora ekranu startowego od wspólnego nagłówka,
  aby edytor E: nie kasował lewego górnego narożnika panelu `ZRODLO` w menu.
- Po wyłączeniu BASIC-u aktualizowany jest również `RAMTOP`, dzięki czemu E:
  może utworzyć ekran w odzyskanym RAM-ie i start z aktywnym BASIC-em nie
  kończy się czarnym ekranem.

### Sprawdzono

- Uruchomienie programu z aktywnym BASIC-em na rzeczywistym Atari 130XE z
  Ultimate 1MB i poprawne działanie interfejsu po przejęciu pamięci.
- Próba na całkowicie standardowym Atari 65XE z 64 KB pozostaje do wykonania.

## [0.6.7] - 2026-08-10

### Zmieniono

- Poszerzono okna `ŹRÓDŁO` i `CEL` o jedną kolumnę oraz zastosowano
  zatwierdzony, opisowy wariant A informacji o nośniku: pojemność, pełna nazwa
  gęstości, geometria, liczba sektorów i wykryty protokół SIO.
- Tytuł sekcji ustawień ma postać `---USTAWIENIA---`, a ekran przed
  kopiowaniem otrzymał wybrany wariant C z osobnymi ramkami `NOŚNIKI` oraz
  `DANE I PAMIĘĆ`.
- Ekran `PARAMETRY KOPII` pokazuje źródło, cel, ich pojemności i tryby SIO,
  geometrię, liczbę sektorów, wymagany i dostępny bufor, liczbę przebiegów,
  formatowanie oraz weryfikację.
- Opisy klawiszy `START` i `SELECT` używają znaku ATASCII 9 oraz jego odmiany
  w negatywie, aby przypominały przechylone klawisze konsoli Atari.
- Wszystkie komentarze w źródłach uporządkowano i pozostawiono po polsku;
  opisują wyłącznie działanie programu, algorytmy, sprzęt i ograniczenia.
- Automatyczne wydanie zawiera teraz notatki zmian pobierane z tego pliku,
  stałe wydanie numerowane oraz zawsze aktualny plik pod tagiem `continuous`.

### Usunięto

- Usunięto z menu linię `SIO: WŁASNE / AUTO`, ponieważ nie była ustawieniem:
  program zawsze używa własnego sterownika i automatycznie dobiera protokół.
- Usunięto użytkową opcję `TEST` oraz jej komunikaty. Skan stacji wykonuje
  pełniejsze sprawdzenie, a kopiowanie i tak zgłasza dokładny błąd sektora.
- Usunięto komunikat o zakończeniu skanowania z głównego ekranu.

### Testy

- Zbudowano XEX i sprawdzono strukturę segmentów, mapę pamięci, geometrię,
  bufor wieloprzebiegowy, własne szybkie SIO, ekran ATASCII oraz obsługę
  klawiszy `START`/`SELECT`.
- Dotychczasowe wersje były dodatkowo sprawdzane przez autora na Atari 130XE
  z Ultimate 1MB i Stereo oraz prawdziwej stacji z HyperXF w formatach SD,
  DD i 720 KB — przy odczycie ze stacji i zapisie na nią.

## [0.6.6] - 2026-08-08

### Dodano

- Pierwsze publiczne wydanie uniwersalnego kopiera całych dyskietek dla Atari
  XL/XE z obsługą D1:–D8:, formatów 90–720 KB, pamięci rozszerzonej, szybkiego
  SIO, HyperXF, formatowania, weryfikacji i ponownego zapisu z bufora.
