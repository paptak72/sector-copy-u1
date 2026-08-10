# Historia zmian

W tym pliku są opisane różnice między kolejnymi opublikowanymi wersjami
Sector Copy U1. Każda wersja ma własny tag i gotowy plik XEX w wydaniach
repozytorium GitHub.

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
