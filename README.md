# Treningi — Mudlet

Pakiet do Mudleta: kalkulator cen treningów umiejętności dla Arkadii MUD. Komenda `/treningi` otwiera okno kalkulatora — obecny poziom umiejętności z kosztu treningu i łączny koszt przedziału treningów.

---

## Jak zainstalować

1. Pobierz `.mpackage` albo `.xml` z [najnowszego wydania](https://github.com/Isithunzi000/arkadia-mudlet-treningi/releases/latest) (oba działają tak samo, wybierz który wolisz)
2. W Mudlecie: **Toolbox → Package Manager** (`Alt+O`) → **Install** i wskaż pobrany plik
3. Gotowe — wpisz `/treningi`

Plik [`treningi.xml`](treningi.xml) w korzeniu repo to źródło pakietu — możesz podejrzeć cały kod bez pobierania.

---

## Komendy

| Komenda | Opis |
|---------|------|
| `/treningi` | otwiera/zamyka okno kalkulatora |
| `/treningi pomoc` | pomoc w konsoli (działa też `/treningi help`) |
| `/treningi tabela` | okno poziomów maksymalnych umiejętności wg zawodu |
| `/treningi aktualizuj` | sprawdza i instaluje aktualizację z GitHub Releases |

## Co liczy kalkulator

- **obecny poziom umiejętności** z kosztu treningu (złoto/srebro/miedź) — przełącznik wybiera, czy podany koszt dotyczy ostatniego czy następnego treningu
- **łączny koszt przedziału treningów** (z poziomu → na poziom, włącznie), z rozbiciem na mithryl/złoto/srebro/miedź
- 39 umiejętności ze zmierzonymi procentami ceny, filtr nad listą
- **cios specjalny** — cena zawsze 100% tabeli; maks. 75% bez polecenia stowarzyszenia, 100% z poleceniem (przełącznik w oknie)
- **inna umiejętność…** — własny procent ceny (1–100) i opcjonalny poziom maksymalny
- **Tabela zawodów** (przycisk w oknie albo `/treningi tabela`): poziomy maksymalne wg zawodu, z poleceniem lub bez; wartości przybliżone oznaczone `~`

## Jak to działa

- model gry: cena treningu z poziomu *i* na *i+1* to `max(1, trunc((3i²−3i+1)·k/100))`, gdzie *k* to procent ceny umiejętności
- waluta: 1 mithryl = 100 zł = 24000 mdz; 1 zł = 240 mdz; 1 sr = 12 mdz
- wszystkie wartości zweryfikowane pomiarami z gry (287/287 kosztów)
- wpisy w polach są oczyszczane: przecinek/kropka obcina resztę, ze śmieci zostają same cyfry, wartości są clampowane
- stan kalkulatora (wybrana umiejętność, pola, przełączniki) zapisuje się na dysku profilu (`treningi_stan_v1.lua`) i wraca po restarcie klienta
- plugin w pełni zgodny z regulaminem gry — czysty kalkulator, zero automatyki, zero wysyłania komend

---

## Aktualizacje

Pakiet sam sprawdza aktualizacje: przy starcie klienta (nie częściej niż co 8 godzin) pyta o najnowsze wydanie na GitHubie i — jeśli jest nowsza wersja — wyświetla powiadomienie. Sam nic nie instaluje: aktualizację uruchamiasz świadomie komendą `/treningi aktualizuj`, która pobiera paczkę, podmienia ją i prosi o restart Mudleta.

Assety wydania mają stałe nazwy (`treningi.mpackage`, `treningi.xml`), a aktualizator przed instalacją sprząta historyczne nazwy pakietów — jedna paczka zostaje w profilu zawsze pod nazwą `treningi`.

---

## Problemy z instalacją

Objaw: `installPackage` zwraca `true`, ale pakiet nie pojawia się na liście i komenda `/treningi` nie działa.

Przyczyna: znany błąd Mudleta — jeśli wcześniejsza próba instalacji się nie powiodła (np. przerwane pobieranie, podwójna instalacja), w katalogu profilu zostaje martwy folder pakietu i każda kolejna instalacja po cichu się nie udaje. Ponawianie nie pomaga — folder trzeba usunąć ręcznie.

Naprawa:

1. W linii poleceń Mudleta wpisz `lua getMudletHomeDir()` i otwórz wyświetlony katalog
2. Skasuj folder `treningi` oraz ewentualny folder nazwany jak pobrany plik bez rozszerzenia — to martwe resztki
3. Zrestartuj profil
4. Zainstaluj pakiet przez **Toolbox → Package Manager** (`Alt+O`) → **Install**
5. Sprawdź `lua getPackages()` — pakiet powinien być na liście, a komenda działać

Jeśli nadal się nie instaluje, sprawdź konsolę główną pod kątem linii `[ ERROR ]` lub `[ WARN ]` tuż po instalacji.

---

Licencja [AGPL-3.0](LICENSE).
