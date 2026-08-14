# Wykrywanie gęstości i pojemności nośnika

Sector Copy U1 rozdziela trzy informacje, które starsze opisy często nazywają
łącznie „gęstością”:

- kodowanie i długość sektora: SD/ED mają 128 B, DD ma 256 B;
- liczbę sektorów na ścieżkę: klasycznie 18 albo 26;
- pojemność logiczną: 720, 1040, 1440, 2080, 2880 albo 4160 sektorów.

## Sekwencja uniwersalna

1. Program odczytuje sektor 1 jako 128 B.
2. Pobiera cztery bajty `STATUS` (`$53`). Dla większości stacji jest to już
   wystarczający wynik rozpoznania nośnika.
3. HyperXF, rozpoznany po trzecim bajcie `$D9`, przechodzi do własnego
   `STATUS U` i badania nagłówków ścieżek `$67`.
4. Jeżeli rodzina XF551 została potwierdzona przez trzeci bajt `$FE` albo
   profil High Speed `$40`, program wykonuje jedną sondę `READ 4/256`, czeka
   dziewięć ramek i pobiera STATUS ponownie. Nie uzależnia sondy od pierwszych
   bitów gęstości, które po błędzie odczytu mogą być stare. Pozostałe stacje
   nie otrzymują tej sondy.
5. Końcowy STATUS wybiera klasę w kolejności: bit 5 → DD, w przeciwnym razie
   bit 7 → ED, a bez obu bitów → SD. Priorytet bitu 5 jest celowy również dla
   nietypowej mieszanej odpowiedzi `$A0`.
6. `GET PERCOM` (`$4E`) jest tylko dokładniejszym kandydatem geometrii. Program
   przyjmuje go, gdy klasa długości sektora zgadza się z końcowym STATUS;
   dla sektorów 128-bajtowych rozróżnienie 18/26 musi być zgodne z SD/ED.

## Dlaczego XF551 wymaga sektora 4

Standardowy ROM XF551 automatycznie przechodzi z FM do MFM, lecz dla MFM
najpierw wybiera ED. Właściwe DD rozpoznaje po tym, że fizyczny sektor jest
dłuższy niż oczekiwane 128 bajtów. Sektory startowe 1–3 są jednak w firmware
jawnie wyłączone z tej kontroli, aby komputer mógł zawsze odczytać 128-bajtowy
boot. Dlatego fizyczny DD daje po `READ 1` pozornie poprawne:

```text
STATUS 1 = $80       ED, 26 × 128 B
PERCOM   = 40/1/26   również ED
```

Obie odpowiedzi są ze sobą zgodne, ale opisują przejściowy stan kontrolera,
nie nośnik. Odczyt sektora 4 nie podlega wyjątkowi. Gdy sektor ma 256 B, ROM
wykrywa dodatkowe dane, przełącza tryb i ponawia ten sam odczyt. Typowy wynik
dla dwustronnego DD jest wtedy następujący:

```text
READ 4/256 = sukces
STATUS 2   = $60       bit 5 DD + bit 6 dwóch stron
PERCOM     = 40/2/18 × 256 B
```

Na prawdziwym ED stacja wysyła dla sondy tylko 128 B. Komputer oczekujący
256 B kończy więc pojedynczą próbę timeoutem; jest to zachowanie oczekiwane.
Następny STATUS nadal zwraca `$80` i to on, nie status samego READ 4,
rozstrzyga klasę nośnika.

Sekwencję `STATUS → READ 4 → STATUS` stosuje QMEG. Źródła Disk Communicatora
3.2 zawierają równoważną prowokację sektorem 4 po rozpoznaniu rodziny XF551.
Sector Copy U1 odtwarza zasadę protokołu, lecz używa własnej implementacji
DCB i wspólnego sterownika HSIO projektu.

## Znaczenie bitów STATUS

Ogólne znaczenie bitów pierwszego bajtu STATUS jest następujące:

| Pierwszy bajt | Znaczenie |
|---:|---|
| `$00` | SD, 18×128 B |
| `$80` | ED, 26×128 B |
| `$20` | DD, 18×256 B, bez ustawionego bitu dwóch stron |
| `$60` | DD, 18×256 B, z ustawionym bitem dwóch stron |

Stockowy XF551 nie wykrywa fizycznie liczby stron i zwykle zgłasza `$60` dla
każdego DD, także nośnika logicznie jednostronnego. Bit 5 jest testowany przed
bitem 7. Pełną kolejność DD → ED → SD potwierdzają QMEG i Disk Communicator;
MyDOS potwierdza pierwszeństwo bitu 5 przy wyborze długości 128/256 B. `$A0`
nie jest typową bezbłędną odpowiedzią stockowego XF551, ale defensywnie również
oznacza sektor DD, ponieważ bit 5 bezpośrednio opisuje długość sektora.

## Dlaczego PERCOM nie rozstrzyga sam

XF551 zwraca konfigurację ostatnio wykrytą albo ostatnio ustawioną przez
`SET PERCOM` — zależnie od tego, co nastąpiło później. Przed sondą sektora 4
stan ED jest dla firmware rzeczywisty, więc PERCOM uczciwie, ale myląco zwraca
26×128. Dopiero końcowy STATUS pozwala ocenić, czy blok odpowiada nośnikowi.

Podobne ograniczenie dotyczy części rozszerzeń 1050: nie wszystkie aktualizują
PERCOM przy zmianie dyskietki. Z tego powodu Sector Copy U1 nigdy nie pozwala
samemu PERCOM zmienić klasy ustalonej przez świeży STATUS.

## Jedna i dwie strony DD

Stockowy XF551 nie potrafi fizycznie wykryć, czy DD ma zapisaną drugą stronę,
i zwykle ustawia profil dwustronny. Nie istnieje uniwersalna sonda sektorowa,
która rozstrzygnie logiczny format 180/360 KB: na nośniku przeformatowanym
jednostronnie mogą pozostać poprawne nagłówki i dane dawnej drugiej strony.
Odczyt sektora 1440 lub kilku sąsiednich sektorów dowodzi wtedy tylko, że
kontroler nadal potrafi je odczytać, nie że należą do bieżącego formatu.

Analiza VTOC może pomóc jedynie dla rozpoznanego DOS-owego systemu plików.
Kopier sektorowy musi obsługiwać również dema, własne loadery i nośniki bez
standardowego VTOC, więc nie może użyć tej informacji jako reguły ogólnej.

Sector Copy U1 przyjmuje zatem dla DD standardowego XF551 domyślne 40T/1S,
720 sektorów i 180 KB. Klawisz `G — GEOMETRIA` pozwala świadomemu użytkownikowi
wybrać 40T/2S, 1440 sektorów i 360 KB. Zmiana źródła lub ponowny skan przywraca
bezpieczny i częstszy wariant 180 KB. Wybór jest następnie używany konsekwentnie
podczas odczytu, kontroli celu, formatowania, zapisu i weryfikacji.

HyperXF potrafi potwierdzić pełne większe nośniki przez tablice nagłówków
skrajnych ścieżek i wtedy 360/720 KB są rozpoznawane automatycznie. Jeżeli
widoczny jest tylko fragment dalszej strony, wynik ma jednak ten sam problem
co standardowy XF551: mogą to być stare nagłówki dyskietki 180 KB. Kopier nie
odrzuca już takiego źródła, lecz przyjmuje 180 KB i udostępnia `G` dla 360 KB.

## Pomocnicza diagnostyka

Polecenie `make diagnostic` tworzy:

```text
build/xf551-density-diagnostic.xex
```

Program pokazuje na jednym, zatrzymanym ekranie wynik i rzeczywisty tryb SIO
operacji READ 1, pierwszego STATUS, READ 4/256, drugiego STATUS oraz wszystkie
bajty PERCOM. Klawisze 1–8 wybierają stację, `S` ponawia pomiar, a `Q` lub
`ESC` wykonuje zimny start. `$FF` przy READ 4 oznacza, że pierwszy STATUS nie
zakończył się poprawnie albo urządzenie nie zostało rozpoznane jako rodzina XF.

## Materiały weryfikacyjne

- [Altirra Hardware Reference Manual — zachowanie i błąd przełączania XF551](https://www.virtualdub.org/downloads/Altirra%20Hardware%20Reference%20Manual.pdf)
- [Disk Communicator 3.2 z kodem źródłowym](https://atari.fox-1.nl/atari-400-800-xl-xe/400-800-xl-xe-tools/diskcomm-3-2-and-source-code/)
- [MyDOS 4.50 z kodem źródłowym](https://atari.fox-1.nl/atari-400-800-xl-xe/400-800-xl-xe-tools/mydos-4-50-with-source/)
- [XF551 SIO-Level Commands](https://www.atarimax.com/freenet/freenet_material/5.8-BitComputersSupportArea/7.TechnicalResourceCenter/showarticle.php?68=)
- [Analiza ROM-u XF551 Adama Górala](https://atarionline.pl/1284924629)
- [ProSystem — praktyczny problem 180 KB widzianego przez XF551 jako dwustronne](https://www.atarimax.com/flashcart/forum/viewtopic.php?f=5&t=884)
- [MyDOS/XF551 Dual Drive Upgrade — ręczne pytanie o dwustronność stacji](https://mathyvannisselroy.nl/css_docs/XF%20Dual%20Drive%20Upgrade.pdf)
