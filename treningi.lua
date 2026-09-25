-- treningi - kalkulator cen treningow Arkadii dla Mudleta (port pluginu Dargoth).
-- Alias /treningi otwiera/zamyka okno kalkulatora. /treningi pomoc - pomoc
-- w konsoli. /treningi tabela - okno tabeli poziomow maksymalnych wg zawodu.
-- /treningi aktualizuj - aktualizacja z GitHub Releases.
--
-- Model gry: cena treningu z poziomu i na i+1 = max(1, trunc((3i^2-3i+1)*k/100)).
-- Waluta: 1 mithryl = 100 zl = 24000 mdz; 1 zl = 240 mdz; 1 sr = 12 mdz.
-- Wszystkie wartosci zweryfikowane pomiarami z gry (287/287 kosztow).
--
-- Plugin w pelni zgodny z regulaminem gry - czysty kalkulator, zero automatyki,
-- zero wysylania komend.

treningi = treningi or {}

do

local PLUGIN_VERSION = "1.0.11"
local PLUGIN_BUILD   = "26-09-2026"

treningi.version = PLUGIN_VERSION
treningi.build   = PLUGIN_BUILD

-- ==========================================================================
-- SILNIK KOSZTOW (matematyka, dane umiejetnosci) - port 1:1 z Dargoth
-- ==========================================================================

local MIEDZ_NA_SREBRO = 12
local MIEDZ_NA_ZLOTO  = 240
local ZLOTE_NA_MITHRYL = 100
local MIN_CENA_TRENINGU = 1
local MAKS_KWOTA  = 999999
local MAKS_POZIOM = 100

-- Bazowy koszt treningu z poziomu i na i+1 przy k=100%: 3*i*i - 3*i + 1.
-- Indeks 0 = 0 (wartownik). Gra liczy czystym wzorem (tabela exe miala
-- 2 literowki: 871@17, 3397@37 - NIE przywracac anomalii).
local KOSZT_BAZOWY = { [0] = 0 }
for i = 1, 100 do KOSZT_BAZOWY[i] = 3 * i * i - 3 * i + 1 end

-- Umiejetnosci i procenty ceny (%) - zmierzone z logow gry 2026-08-26,
-- poza szacowanie (z oryginalnego kalkulatora, niezmierzone).
local UMIEJETNOSCI = {
  { nazwa = "akrobatyka", procent = 70 },
  { nazwa = "alchemia", procent = 70 },
  { nazwa = "blokowanie wyjscia", procent = 100 },
  { nazwa = "bronie drzewcowe", procent = 80 },
  { nazwa = "kieszonkostwo", procent = 70 },
  { nazwa = "lowiectwo", procent = 50 },
  { nazwa = "maczugi", procent = 50 },
  { nazwa = "miecze", procent = 100 },
  { nazwa = "mierzony cios", procent = 100 },
  { nazwa = "mloty", procent = 80 },
  { nazwa = "ocena obiektu", procent = 50 },
  { nazwa = "ocena przeciwnika", procent = 50 },
  { nazwa = "opieka nad zwierzetami", procent = 50 },
  { nazwa = "otwieranie zamkow", procent = 70 },
  { nazwa = "parowanie", procent = 80 },
  { nazwa = "plywanie", procent = 50 },
  { nazwa = "rozkazy", procent = 100 },
  { nazwa = "skradanie sie", procent = 70 },
  { nazwa = "spostrzegawczosc", procent = 50 },
  { nazwa = "szacowanie", procent = 50 },
  { nazwa = "sztylety", procent = 46 },
  { nazwa = "tarczownictwo", procent = 80 },
  { nazwa = "targowanie sie", procent = 50 },
  { nazwa = "topory", procent = 70 },
  { nazwa = "tropienie", procent = 50 },
  { nazwa = "ukrywanie sie", procent = 70 },
  { nazwa = "uniki", procent = 80 },
  { nazwa = "walka bez broni", procent = 90 },
  { nazwa = "walka dwiema bronmi", procent = 100 },
  { nazwa = "walka pokazowa", procent = 100 },
  { nazwa = "walka w ciemnosci", procent = 95 },
  { nazwa = "walka w szyku", procent = 100 },
  { nazwa = "wspinaczka", procent = 50 },
  { nazwa = "wyczucie kierunku", procent = 50 },
  { nazwa = "wykrywanie pulapek", procent = 70 },
  { nazwa = "zaslanianie", procent = 100 },
  { nazwa = "zielarstwo", procent = 70 },
  { nazwa = "znajomosc jezykow", procent = 50 },
}

-- Pozycje specjalne na liscie (za umiejetnosciami):
local CIOS_IDX = #UMIEJETNOSCI + 1 -- cios specjalny (umiejetnosc specjalna)
local INNA_IDX = #UMIEJETNOSCI + 2 -- "inna umiejetnosc..."

-- Cios specjalny: cena zawsze 100% tabeli; maks. 75 (bez przelacznika
-- z/bez polecenia - decyzja ownera 2026-09-25, procenty swiadomie od/do).
local CIOS_PROCENT  = 100
local CIOS_MAX      = 75

local function naMiedz(zl, sr, mdz)
  return zl * MIEDZ_NA_ZLOTO + sr * MIEDZ_NA_SREBRO + mdz
end

-- Rozbicie kwoty w miedzi na mithryl/zloto/srebro/miedz.
local function zMiedzi(miedzi)
  local zloteRazem = math.floor(miedzi / MIEDZ_NA_ZLOTO)
  local reszta = miedzi % MIEDZ_NA_ZLOTO
  return {
    miedziRazem = miedzi,
    mithryl = math.floor(zloteRazem / ZLOTE_NA_MITHRYL),
    zloto = zloteRazem % ZLOTE_NA_MITHRYL,
    srebro = math.floor(reszta / MIEDZ_NA_SREBRO),
    miedz = reszta % MIEDZ_NA_SREBRO,
  }
end

-- Cena treningu z poziomu i na i+1 przy procencie ceny k (%).
-- Dokladnie tak liczy gra: max(1, trunc(KOSZT_BAZOWY[i] * k / 100)).
local function cenaTreningu(poziom, procentCeny)
  return math.max(MIN_CENA_TRENINGU,
                  math.floor(KOSZT_BAZOWY[poziom] * procentCeny / 100))
end

-- Obecny poziom umiejetnosci na podstawie kosztu treningu.
-- Pierwszy poziom i z cenaTreningu(i,k) >= koszt; poziom = i+1 dla
-- 'ostatni', i dla 'nastepny', obciety do 100. Koszt ponad maks -> 100.
local function obecnyPoziom(zl, sr, mdz, procentCeny, tryb)
  local miedzi = naMiedz(zl, sr, mdz)
  for i = 0, MAKS_POZIOM do
    if cenaTreningu(i, procentCeny) >= miedzi then
      return math.min(tryb == "ostatni" and i + 1 or i, MAKS_POZIOM)
    end
  end
  return MAKS_POZIOM
end

-- Laczny koszt treningow w przedziale [od, doo] WLACZNIE; kazdy trening
-- liczony osobno. maks (opcjonalny): koniec powyzej maksimum obcinany
-- (wynik.obcietyDo); przedzial w calosci powyzej -> nil. nil tez gdy doo < od.
local function kosztPrzedzialu(od, doo, procentCeny, maks)
  if doo - od < 0 then return nil end
  if maks ~= nil and od > maks then return nil end
  local doRzeczywiste = maks ~= nil and math.min(doo, maks) or doo
  local suma = 0
  for i = od, doRzeczywiste do
    suma = suma + cenaTreningu(i, procentCeny)
  end
  local wynik = zMiedzi(suma)
  if doRzeczywiste ~= doo then wynik.obcietyDo = doRzeczywiste end
  return wynik
end

-- Dowolny wpis uzytkownika -> liczba calkowita z [0, maks].
-- Biale znaki obcinane; pusty -> 0; przecinek/kropka obcina reszte;
-- ze smieci zostaja same cyfry ("1 234 mdz" -> 1234); clamp do [0, maks].
local function sanitizujLiczbe(wpis, maks)
  local czysty = tostring(wpis or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if czysty == "" then return 0 end
  local sep = czysty:find("[.,]")
  local calk = sep and czysty:sub(1, sep - 1) or czysty
  local cyfry = calk:gsub("%D+", "")
  if cyfry == "" then return 0 end
  local n = tonumber(cyfry)
  if not n then return 0 end
  n = math.floor(n)
  if n < 0 then return 0 end
  if n > maks then return maks end
  return n
end

-- Wpis "poziom maksymalny" -> limit albo nil (bez limitu). Pusty, smieci
-- lub >= 100 = brak limitu. Wartosci 1-99 zwracane jako limit.
local function limitZWpisu(wpis)
  local czysty = tostring(wpis or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if czysty == "" then return nil end
  local sep = czysty:find("[.,]")
  local calk = sep and czysty:sub(1, sep - 1) or czysty
  local cyfry = calk:gsub("%D+", "")
  if cyfry == "" then return nil end
  local n = tonumber(cyfry)
  if not n then return nil end
  if n >= MAKS_POZIOM then return nil end
  return math.max(1, math.floor(n))
end

-- Przedzial [od, do] porzadkowany rosnaco.
local function porzadkujPrzedzial(od, doo)
  if od <= doo then return od, doo end
  return doo, od
end

-- Grupowanie tysiecy (1234567 -> "1 234 567").
local function formatujLiczbe(n)
  local s = tostring(n)
  local r = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
  return (r:gsub("^%s", ""))
end

-- ==========================================================================
-- POZIOMY MAKSYMALNE WG ZAWODU (dane + limitDla) - port 1:1 z Dargoth
-- Wartosc -1 = zawod nie oferuje umiejetnosci (kreska w tabeli).
-- ==========================================================================

local ZAWODY = {
  "Partyzant", "Fanatyk", "Legionista", "Gladiator", "Korsarz", "Straznik",
  "Lancknecht", "Nozownik", "Barbarzynca", "Mysliwy", "Kupiec", "Odkrywca",
  "Gildia Podroznikow",
}
-- Skroty 1:1 z klientem www/Dargoth; ogonki jako escape'y UTF-8 (repo ASCII):
-- \197\188 = z kropka, \197\155 = s z akcentem.
local ZAWODY_SKROTY = {
  "Part", "Fan", "Leg", "Glad", "Kors", "Stra\197\188", "Lanc", "No\197\188",
  "Barb", "My\197\155l", "Kup", "Odkr", "GP",
}

local TABELA_POZIOMOW = {
  { um = "bron", limity = { 70, 74, 71, 75, 73, 74, 71, 72, 71, 65, -1, 60, 30 } },
  { um = "uniki", limity = { 60, 45, 30, 42, 40, 50, 51, 70, 45, 55, -1, 34, 25 } },
  { um = "walka dwiema bronmi", limity = { 50, 65, -1, -1, -1, -1, -1, 55, -1, -1, -1, -1, 19 } },
  { um = "tarczownictwo", limity = { -1, -1, 75, 60, 71, -1, -1, -1, -1, -1, -1, -1, 25 } },
  { um = "parowanie", limity = { 40, 45, 50, 41, -1, 71, 71, -1, 55, -1, -1, 45, 25 } },
  { um = "zaslanianie", limity = { 45, 46, 41, 40, 60, 60, 40, 40, 41, -1, -1, -1, 20 } },
  { um = "blokowanie wyjscia", limity = { 38, 44, -1, -1, 41, 55, -1, 51, 45, -1, -1, -1, 20 } },
  { um = "rozkazy", limity = { 30, -1, 55, 30, 40, 50, 55, -1, -1, -1, -1, -1, 15 } },
  { um = "walka w szyku", limity = { -1, 35, 75, 35, 45, 55, 50, -1, 31, -1, -1, -1, 15 } },
  { um = "walka bez broni", limity = { -1, -1, 60, 55, 55, -1, -1, -1, 60, -1, -1, -1, 17 } },
  { um = "walka w ciemnosci", limity = { -1, -1, 60, 55, 55, -1, -1, -1, -1, -1, -1, -1, 15 } },
  { um = "ukrywanie", limity = { 80, -1, -1, -1, -1, -1, -1, 70, -1, 80, -1, -1, 30 } },
  { um = "skradanie", limity = { 80, -1, -1, -1, -1, -1, -1, 70, -1, 80, -1, -1, 24 } },
  { um = "tropienie", limity = { 60, 50, -1, -1, -1, -1, -1, -1, -1, 75, -1, -1, 30 } },
  { um = "zielarstwo", limity = { -1, -1, -1, -1, -1, -1, -1, -1, -1, 59, 55, 41, 18 } },
  { um = "spostrzegawczosc", limity = { 70, -1, -1, -1, -1, 65, -1, 70, -1, 75, 60, 71, 50 } },
  { um = "wyczucie kierunku", limity = { 60, -1, -1, -1, 45, -1, -1, -1, -1, 60, -1, 84, 30 } },
  { um = "plywanie", limity = { 55, -1, -1, -1, 85, -1, -1, -1, -1, 55, -1, 71, 42 } },
  { um = "wspinaczka", limity = { 60, -1, -1, -1, 60, -1, -1, -1, -1, 60, -1, 71, 50 } },
  { um = "ocena przeciwnika", limity = { -1, 50, 65, 85, 60, 65, 65, 85, 55, 54, 50, 50, 21 } },
  { um = "ocena obiektu", limity = { -1, -1, 50, 50, 45, 55, 50, 50, 35, 40, 85, 41, 21 } },
  { um = "lowiectwo", limity = { 40, -1, -1, -1, -1, -1, -1, -1, -1, 77, -1, 41, 25 } },
  { um = "opieka nad zwierzetami", limity = { -1, -1, -1, -1, -1, -1, -1, -1, -1, 74, -1, 44, 24 } },
  { um = "wykrywanie pulapek", limity = { -1, -1, -1, -1, -1, -1, -1, -1, -1, 55, -1, 55, 22 } },
  { um = "otwieranie zamkow", limity = { -1, -1, -1, -1, -1, -1, -1, 50, -1, -1, -1, -1, 15 } },
  { um = "znajomosc jezykow", limity = { -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 70, 85, 40 } },
  { um = "targowanie sie", limity = { -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 55, 42, 30 } },
  { um = "szacowanie", limity = { -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 80, 50, 30 } },
  { um = "alchemia", limity = { -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 20 } },
  { um = "akrobatyka", limity = { -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 13 } },
}

local function znajdzWiersz(um)
  for _, w in ipairs(TABELA_POZIOMOW) do
    if w.um == um then return w end
  end
  return nil
end

local function indexZawodu(zawod)
  for i, z in ipairs(ZAWODY) do
    if z == zawod then return i end
  end
  return nil
end

-- Poziom maksymalny umiejetnosci dla sytuacji postaci.
-- zawod = nil -> czyste GP. Zawod oferuje: z poleceniem = wartosc zawodu,
-- bez = GP + 75% roznicy (zaokraglone). Nie oferuje (kreska) -> jak GP.
-- Nieznana umiejetnosc -> nil.
local function limitDla(um, zawod, polecenie)
  local w = znajdzWiersz(um)
  if not w then return nil end
  local gp = w.limity[#ZAWODY]
  if gp < 0 then return nil end
  if zawod == nil then return gp end
  local idx = indexZawodu(zawod)
  if not idx then return nil end
  local z = w.limity[idx]
  if z < 0 then return gp end
  if polecenie then return z end
  return math.floor(gp + 0.75 * (z - gp) + 0.5)
end

-- Limit do wyswietlenia w tabeli zawodow: { wartosc, przyblizona } albo nil.
-- Z poleceniem: dokladna. Bez: GP i kreski dokladne, reszta przyblizona.
local function limitWyswietlany(um, zawod, polecenie)
  local w = znajdzWiersz(um)
  if not w then return nil end
  local idx = indexZawodu(zawod)
  if not idx then return nil end
  local gp = w.limity[#ZAWODY]
  if gp < 0 then return nil end
  local z = w.limity[idx]
  local czyGP = idx == #ZAWODY
  if polecenie then
    local v = z >= 0 and z or gp
    return { wartosc = v, przyblizona = false }
  end
  if czyGP or z < 0 then
    return { wartosc = gp, przyblizona = false }
  end
  return { wartosc = math.floor(gp + 0.75 * (z - gp) + 0.5), przyblizona = true }
end

-- ==========================================================================
-- STAN (zapis na dysku profilu, jak w kalendarzach/truwerze)
-- ==========================================================================

local STAN_PATH = getMudletHomeDir() .. "/treningi_stan_v1.lua"

local STAN_DOMYSLNY = {
  umiejetnosc = -1,        -- indeks w UMIEJETNOSCI; -1 = nic; CIOS/INNA_IDX
  tryb = "ostatni",        -- "ostatni" | "nastepny"
  zloto = "", srebro = "", miedz = "",
  od = "", doo = "",
  innaProcent = "100",     -- procent ceny dla "innej umiejetnosci" (1-100)
  innaMaxPoziom = "",      -- poziom maksymalny dla "innej" (pusty = bez limitu)
}

local stan = { filtr = "" }
for k, v in pairs(STAN_DOMYSLNY) do stan[k] = v end

local function wczytajStan()
  -- Semantyka Mudleta (zweryfikowana E2E na Mudlet 5.0.1): table.load bez
  -- tabeli docelowej zwraca nil; z tabela docelowa wypelnia ja plasko
  -- kluczami pierwszego zapisanego elementu. Fallback t[1] na wypadek
  -- starszych zapisow w innych wersjach klienta.
  local t = {}
  local ok = pcall(table.load, STAN_PATH, t)
  if not ok then return end
  if type(t[1]) == "table" and t.umiejetnosc == nil then t = t[1] end
  if t.umiejetnosc == nil and t.zloto == nil then return end
  if type(t.umiejetnosc) == "number"
     and t.umiejetnosc >= 0 and t.umiejetnosc <= INNA_IDX then
    stan.umiejetnosc = t.umiejetnosc
  end
  if t.tryb == "nastepny" or t.tryb == "ostatni" then stan.tryb = t.tryb end
  for _, k in ipairs({ "zloto", "srebro", "miedz", "od", "doo" }) do
    if type(t[k]) == "string" then stan[k] = t[k] end
  end
  if type(t.innaProcent) == "string"
     and sanitizujLiczbe(t.innaProcent, 100) >= 1 then
    stan.innaProcent = tostring(sanitizujLiczbe(t.innaProcent, 100))
  end
  if type(t.innaMaxPoziom) == "string" and limitZWpisu(t.innaMaxPoziom) ~= nil then
    stan.innaMaxPoziom = tostring(limitZWpisu(t.innaMaxPoziom))
  end
  -- Pole polecenie ze starej wersji celowo ignorowane (przelacznik
  -- z/bez polecenia usuniety z okna glownego; cios liczy z limitem 75%).
end

local function zapiszStan()
  local t = {}
  for k in pairs(STAN_DOMYSLNY) do t[k] = stan[k] end
  pcall(table.save, STAN_PATH, t)
end

local function aktualnyProcent()
  if stan.umiejetnosc == INNA_IDX then
    return math.max(1, sanitizujLiczbe(stan.innaProcent, 100))
  end
  if stan.umiejetnosc == CIOS_IDX then return CIOS_PROCENT end
  local u = UMIEJETNOSCI[stan.umiejetnosc]
  return u and u.procent or 100
end

-- Poziom maksymalny dla wybranej pozycji; nil = bez limitu.
local function aktualnyMaks()
  if stan.umiejetnosc == INNA_IDX then return limitZWpisu(stan.innaMaxPoziom) end
  if stan.umiejetnosc == CIOS_IDX then return CIOS_MAX end
  return nil
end

local function nazwaWybranej()
  if stan.umiejetnosc == CIOS_IDX then return "cios specjalny" end
  if stan.umiejetnosc == INNA_IDX then return "inna umiejetnosc" end
  local u = UMIEJETNOSCI[stan.umiejetnosc]
  return u and u.nazwa or ""
end

-- ==========================================================================
-- GUI (Geyser; wzorzec truwer/pasek: Adjustable.Container + pulowane widgety)
-- ==========================================================================

local gui = { managed = {}, fields = {}, rows = {}, open = false,
              tabPolecenie = true }
treningi.gui = gui

-- Paleta: ciemny granat z niebieskim akcentem, wysoki kontrast rol
-- (naglowki sekcji, pola, wynik, nominaly) - nic sie nie zlewa.
-- Paleta 1:1 z wtyczka Dargoth (klient www): te same hex co w jej CSS.
local STYLE = {
  btn     = "background-color:#23233a;color:#b9b9d6;border:1px solid #3d3d5c;border-radius:8px;",
  primary = "background-color:#31437a;color:#ffffff;border:1px solid #7aa2f7;border-radius:8px;font-weight:bold;",
  field   = "background-color:#23233a;color:#e6e6f0;border:1px solid #3d3d5c;border-radius:8px;",
  wybrana = "background-color:#23233a;color:#9fc0ff;border:1px solid #3d3d5c;border-radius:7px;",
  title   = "color:#e6e6f0;background-color:transparent;",
  meta    = "color:#9a9ab5;font-weight:bold;background-color:transparent;",
  lbl     = "color:#9a9ab5;background-color:transparent;",
  nota    = "color:#8c8ca8;font-style:italic;background-color:transparent;",
  row     = "background-color:transparent;color:#d8d8e8;border-bottom:1px solid #26263e;",
  rowSpec = "background-color:transparent;color:#d8d8e8;border-bottom:1px solid #26263e;",
  rowSel  = "background-color:#31437a;color:#ffffff;border-bottom:1px solid #26263e;font-weight:bold;",
  panel   = "background-color:#1d1d30;color:#7aa2f7;font-size:30px;font-weight:bold;border:1px solid #3d3d5c;border-radius:8px;",
  panelLbl= "color:#9a9ab5;background-color:transparent;",
  mth     = "background-color:#2c3d66;color:#9fc0ff;border-radius:10px;font-weight:bold;",
  zl      = "background-color:#4d4020;color:#ffd766;border-radius:10px;font-weight:bold;",
  sr      = "background-color:#3c3c46;color:#d5d5e0;border-radius:10px;font-weight:bold;",
  mz      = "background-color:#4a3128;color:#e8a87c;border-radius:10px;font-weight:bold;",
  dotZl   = "background-color:#d4af37;border-radius:4px;",
  dotSr   = "background-color:#b8b8c0;border-radius:4px;",
  dotMz   = "background-color:#b5724a;border-radius:4px;",
  footlink= "color:#9a9ab5;background-color:transparent;border:none;qproperty-alignment: AlignRight;",
  listaBg = "background-color:#1d1d30;border:1px solid #3d3d5c;border-radius:8px;",
}

-- Ciemny styl kontenerow zamiast domyslnej bialej ramki "groove white"
-- (Adjustable.Container przyjmuje adjLabelstyle/buttonstyle w konstruktorze;
-- okna pozostaja przesuwalne i skalowalne mysza).
local ADJ_STYLE = [[background-color:#16161e;border:1px solid #3d3d5c;]]
local ADJ_BTN_STYLE = [[
QLabel{ background-color:#16161e;color:#9a9ab5;border:1px solid #3d3d5c; }
QLabel::hover{ background-color:#31437a;color:#ffffff; }
]]

-- Granice wnetrza okna (jak w truwerze, zmierzone na zywym kliencie):
-- Tresc konczy sie na x=610, a okno ma 670 px (610 + padding 30 lewy +
-- padding 30 prawy): Inside w Geyserze ma z natury zerowy prawy margines,
-- wiec symetryczny margines uzyskujemy poszerzeniem okna o padding.
-- Dolna widoczna granica tresci to y+h =< 540.
local RIGHT_EDGE  = 610
-- CONT_PAD (padding kontenerow) = 30 - definicja nizej, tu wartosc
-- wkomponowana w stale szerokosci.
local WIN_W       = 670  -- 610 + 2 * 30 (symetria marginesow)
local TAB_W       = 910  -- 10 + 840 konsola + 2 * 30
local FOOTER_Y    = 514

local function applyStyle(l, css)
  if l and type(l.setStyleSheet) == "function" then l:setStyleSheet(css) end
end

local function mk(name, x, y, wd, h, container)
  local l = gui.managed[name]
  if not l then
    l = Geyser.Label:new({ name = name, x = x, y = y, width = wd, height = h },
                         container or gui.win)
    gui.managed[name] = l
  else
    l:move(x, y)
    l:resize(wd, h)
  end
  return l
end

local function setText(name, s)
  echo(name, s)
end

local function txt(name, x, y, wd, h, text, container, style)
  local l = mk(name, x, y, wd, h, container)
  setText(name, text)
  if style then applyStyle(l, style) end
  l:show()
  return l
end

-- Klik dowolnego przycisku najpierw splukuje pola (wpis bez Entera trafia
-- do stanu), dopiero potem wykonuje akcje (jak w truwerze).
local function btn(name, x, y, wd, label, fn, container, style)
  local l = mk(name, x, y, wd, 24, container)
  setText(name, label)
  applyStyle(l, style or STYLE.btn)
  l:setClickCallback(function()
    gui.flushFields()
    fn()
  end)
  l:show()
  return l
end

local function mkLine(name, x, y, wd, h, container)
  local l = gui.managed[name]
  if not l then
    l = Geyser.CommandLine:new({ name = name, x = x, y = y, width = wd, height = h },
                               container or gui.win)
    gui.managed[name] = l
  else
    l:move(x, y)
    l:resize(wd, h)
  end
  return l
end

-- Linia z tekstem poczatkowym i commitem na Enter (setAction).
local function line(name, x, y, wd, text, fn, container)
  local l = mkLine(name, x, y, wd, 24, container)
  applyStyle(l, STYLE.field)
  l:print(text)
  l:setAction(function(t)
    gui.flushFields(name)
    fn(t)
    zapiszStan()
    gui.render()
  end)
  l:show()
  return l
end

-- Rejestr pol do splukiwania: commit zapisuje do stanu i odswieza.
local function pole(name, x, y, wd, text, commit, container)
  gui.fields[name] = { value = text, commit = commit }
  return line(name, x, y, wd, text, function(t)
    commit(t)
    gui.fields[name].value = t
  end, container)
end

-- Odczyt biezacego tekstu pola: getCmdLine (Mudlet 3.1+), fallback na
-- getText widgetu (starsze wersje/stuby).
local function odczytPola(name)
  if type(getCmdLine) == "function" then
    local ok, t = pcall(getCmdLine, name)
    if ok and type(t) == "string" then return t end
  end
  local w = gui.managed[name]
  if w and type(w.getText) == "function" then
    local ok, t = pcall(w.getText, w)
    if ok and type(t) == "string" then return t end
  end
  return nil
end

function gui.flushFields(exceptName)
  for name, f in pairs(gui.fields) do
    if name ~= exceptName then
      local t = odczytPola(name)
      if t and t ~= f.value then
        f.commit(t)
        f.value = t
      end
    end
  end
end

local renderLista -- fwd: gui.poll (wyzej) odswieza liste po zmianie filtra

-- Podniesienie interaktywnych widgetow okna NAD wiersze listy: na Mudlet
-- Web wiersze ScrollBox nie sa clipowane przez pojemnik i ich przezroczyste
-- overlaye przykrywaja przyciski/pola w dolnej czesci okna (bug E2E web:
-- klikniecie Tabela trafialo w niewidzialny wiersz listy). raiseWindow jest
-- no-op, jesli klient go nie ma (starsze Mudlety). Wywolywane po kazdym
-- renderze listy, bo filtrowanie tworzy wiersze od nowa.
local function podniesInteraktywne()
  if type(raiseWindow) ~= "function" then return end
  for name, _ in pairs(gui.managed) do
    if name ~= "trng.lista" and not name:match("^trng.row%.") then
      pcall(raiseWindow, name)
    end
  end
end

-- Live odczyt pol bez Entera (jak event "input" w kliencie www): cykliczny
-- poll getCmdLine; zmiana filtra odswieza liste, zmiana innych pol wynik.
-- Poll NIGDY nie wywoluje gui.render (print do pola kasowalby wpisywanie).
function gui.poll()
  if not gui.open then return end
  local zmianaFiltra, zmianaInnych, jakas = false, false, false
  for name, f in pairs(gui.fields) do
    local t = odczytPola(name)
    if t and t ~= f.value then
      f.commit(t)
      f.value = t
      jakas = true
      if name == "trng.filtr" then zmianaFiltra = true else zmianaInnych = true end
    end
  end
  if not jakas then return end
  zapiszStan()
  if zmianaFiltra then renderLista() end
  if zmianaInnych then gui.odswiez() end
end

-- ---------------------------------------------------------------------------
-- Lista umiejetnosci (ScrollBox, filtr, pozycje specjalne na koncu)
-- ---------------------------------------------------------------------------

local ROW_H = 22

local function wpisyListy()
  local f = string.lower(stan.filtr or "")
  local out = {}
  for i, u in ipairs(UMIEJETNOSCI) do
    if f == "" or string.find(string.lower(u.nazwa), f, 1, true) then
      out[#out + 1] = { idx = i, nazwa = u.nazwa, procent = u.procent }
    end
  end
  if f == "" or string.find("cios specjalny", f, 1, true) then
    out[#out + 1] = { idx = CIOS_IDX, nazwa = "cios specjalny", procent = CIOS_PROCENT }
  end
  if f == "" or string.find("inna umiejetnosc", f, 1, true) then
    out[#out + 1] = { idx = INNA_IDX, nazwa = "inna umiejetnosc...", procent = nil }
  end
  return out
end

renderLista = function()
  if not gui.lista then return end
  local wpisy = wpisyListy()
  for i, w in ipairs(wpisy) do
    local name = "trng.row." .. i
    local l = gui.rows[i]
    if not l then
      l = Geyser.Label:new({ name = name, x = 0, y = (i - 1) * ROW_H,
                             width = "100%", height = ROW_H }, gui.lista)
      gui.rows[i] = l
    else
      l:move(0, (i - 1) * ROW_H)
    end
    local opis = w.nazwa .. (w.procent and ("  (k=" .. w.procent .. "%)") or "")
    l:echo(opis)
    if w.idx == stan.umiejetnosc then
      applyStyle(l, STYLE.rowSel)
    elseif w.idx >= CIOS_IDX then
      applyStyle(l, STYLE.rowSpec)
    else
      applyStyle(l, STYLE.row)
    end
    local idx = w.idx
    l:setClickCallback(function()
      gui.flushFields()
      stan.umiejetnosc = idx
      zapiszStan()
      gui.odswiez()
    end)
    l:show()
  end
  for i = #wpisy + 1, #gui.rows do
    gui.rows[i]:hide()
  end
  podniesInteraktywne()
end

-- ---------------------------------------------------------------------------
-- Odswiezenie wynikow ze stanu (jak aktualizuj() w Dargoth)
-- ---------------------------------------------------------------------------

local function setLbl(name, text)
  local l = gui.managed[name]
  if l then l:echo(text) end
end

-- echo() w Mudlet 5.0.1 resetuje font/kolor z CSS labelki, wiec duzy wynik
-- i kolorowe teksty chipow ida w <span style="..."> (zmierzone na zywym
-- kliencie: samo font-size/color w setStyleSheet nie dziala na echo).
local function wynikHtml(s)
  return '<span style="font-size:30px;color:#7aa2f7;font-weight:bold;">'
         .. s .. "</span>"
end

-- Kolory tekstu chipow nominalow 1:1 z Dargoth (klucz = skrot nominalu).
local CHIP_FG = { mth = "#9fc0ff", zl = "#ffd766", sr = "#d5d5e0",
                  mdz = "#e8a87c" }

local function chipHtml(tekst, nominal)
  return '<span style="color:' .. CHIP_FG[nominal] .. ';"> '
         .. tekst .. " </span>"
end

local function showLbl(name, on)
  local l = gui.managed[name]
  if not l then return end
  if on then l:show() else l:hide() end
end

function gui.odswiez()
  renderLista()

  local czyInna = stan.umiejetnosc == INNA_IDX
  local czyCios = stan.umiejetnosc == CIOS_IDX
  showLbl("trng.innaProc.lbl", czyInna)
  showLbl("trng.innaProc", czyInna)
  showLbl("trng.innaMax.lbl", czyInna)
  showLbl("trng.innaMax", czyInna)

  if stan.umiejetnosc < 0 then
    setLbl("trng.poziom", wynikHtml("-"))
    setLbl("trng.podpowiedz", "Wybierz umiejetnosc z listy powyzej.")
    showLbl("trng.podpowiedz", true)
    showLbl("trng.wybrana", false)
    for _, n in ipairs({ "trng.chip.mth", "trng.chip.zl", "trng.chip.sr", "trng.chip.mz",
                         "trng.razem", "trng.notka" }) do
      showLbl(n, false)
    end
    return
  end

  local k = aktualnyProcent()
  setLbl("trng.wybrana", "Wybrana: " .. nazwaWybranej() ..
         "  -  " .. k .. "% ceny bazowej")
  showLbl("trng.wybrana", true)
  showLbl("trng.podpowiedz", false)

  local zl = sanitizujLiczbe(stan.zloto, MAKS_KWOTA)
  local sr = sanitizujLiczbe(stan.srebro, MAKS_KWOTA)
  local mz = sanitizujLiczbe(stan.miedz, MAKS_KWOTA)
  local poziom = obecnyPoziom(zl, sr, mz, k, stan.tryb)
  setLbl("trng.poziom", wynikHtml(poziom .. "%"))

  local od = sanitizujLiczbe(stan.od, MAKS_POZIOM)
  local doo = sanitizujLiczbe(stan.doo, MAKS_POZIOM)
  local odP, doP = porzadkujPrzedzial(od, doo)
  local maks = aktualnyMaks()
  local wynik = kosztPrzedzialu(odP, doP, k, maks)

  if not wynik then
    for _, n in ipairs({ "trng.chip.mth", "trng.chip.zl", "trng.chip.sr", "trng.chip.mz",
                         "trng.razem" }) do
      showLbl(n, false)
    end
    if maks ~= nil and odP > maks then
      setLbl("trng.notka", "Ten zakres jest poza zasiegiem - poziom maksymalny to " ..
             maks .. "%.")
      showLbl("trng.notka", true)
    else
      showLbl("trng.notka", false)
    end
    return
  end

  local chips = {
    { "trng.chip.mth", wynik.mithryl, "mth" },
    { "trng.chip.zl", wynik.zloto, "zl" },
    { "trng.chip.sr", wynik.srebro, "sr" },
    { "trng.chip.mz", wynik.miedz, "mdz" },
  }
  local puste = true
  for _, c in ipairs(chips) do
    if c[2] > 0 then
      setLbl(c[1], chipHtml(formatujLiczbe(c[2]) .. " " .. c[3], c[3]))
      showLbl(c[1], true)
      puste = false
    else
      showLbl(c[1], false)
    end
  end
  if puste then
    setLbl("trng.chip.mz", chipHtml("0 mdz", "mdz"))
    showLbl("trng.chip.mz", true)
  end

  showLbl("trng.razem", true)

  if wynik.obcietyDo ~= nil then
    setLbl("trng.notka", "poziom maksymalny to " .. wynik.obcietyDo ..
           "% - policzono " .. odP .. "% -> " .. wynik.obcietyDo .. "%")
    showLbl("trng.notka", true)
  elseif od ~= odP or doo ~= doP then
    setLbl("trng.notka", "policzono " .. odP .. "% -> " .. doP .. "%")
    showLbl("trng.notka", true)
  else
    showLbl("trng.notka", false)
  end
end

-- ---------------------------------------------------------------------------
-- Budowa okna kalkulatora
-- ---------------------------------------------------------------------------

local function trybBtnRefresh()
  local a = gui.managed["trng.tryb.ostatni"]
  local b = gui.managed["trng.tryb.nastepny"]
  if a then applyStyle(a, stan.tryb == "ostatni" and STYLE.primary or STYLE.btn) end
  if b then applyStyle(b, stan.tryb == "nastepny" and STYLE.primary or STYLE.btn) end
end

function gui.render()
  if not gui.win then return end

  -- Filtr listy + wybrana pozycja
  pole("trng.filtr", 10, 4, 290, stan.filtr or "", function(t)
    stan.filtr = t
    renderLista()
  end)
  txt("trng.wybrana", 310, 4, 300, 24, "", gui.win, STYLE.wybrana)

  -- Lista umiejetnosci
  if not gui.lista then
    gui.lista = Geyser.ScrollBox:new({ name = "trng.lista", x = 10, y = 32,
                                       width = 600, height = 150 }, gui.win)
    applyStyle(gui.lista, STYLE.listaBg)
  end
  renderLista()

  -- Sekcja: koszt treningu -> poziom
  txt("trng.sec1", 10, 188, 400, 16, "KOSZT TRENINGU -> POZIOM", gui.win, STYLE.meta)
  -- Etykiety pol walut z kolorowymi kropkami (jak .trng-kropka w Dargoth)
  txt("trng.dot.zl", 12, 209, 8, 8, "", gui.win, STYLE.dotZl)
  txt("trng.dot.sr", 215, 209, 8, 8, "", gui.win, STYLE.dotSr)
  txt("trng.dot.mz", 418, 209, 8, 8, "", gui.win, STYLE.dotMz)
  txt("trng.zl.lbl", 26, 206, 177, 14, "zloto (zl)", gui.win, STYLE.lbl)
  txt("trng.sr.lbl", 229, 206, 177, 14, "srebro (sr)", gui.win, STYLE.lbl)
  txt("trng.mz.lbl", 432, 206, 178, 14, "miedz (mdz)", gui.win, STYLE.lbl)
  pole("trng.zl", 10, 222, 193, stan.zloto, function(t) stan.zloto = t end)
  pole("trng.sr", 213, 222, 193, stan.srebro, function(t) stan.srebro = t end)
  pole("trng.mz", 416, 222, 194, stan.miedz, function(t) stan.miedz = t end)

  -- Tryb kosztu (ostatni/nastepny)
  btn("trng.tryb.ostatni", 10, 252, 297, "Podany koszt: ostatni trening",
      function() stan.tryb = "ostatni"; zapiszStan(); gui.odswiez(); trybBtnRefresh() end)
  btn("trng.tryb.nastepny", 313, 252, 297, "Podany koszt: nastepny trening",
      function() stan.tryb = "nastepny"; zapiszStan(); gui.odswiez(); trybBtnRefresh() end)
  trybBtnRefresh()

  -- Wynik poziomu
  txt("trng.poziom", 10, 282, 600, 46, "-", gui.win, STYLE.panel)
  txt("trng.podpowiedz", 10, 332, 600, 18, "", gui.win, STYLE.meta)

  -- Sekcja: koszt przedzialu
  txt("trng.sec2", 10, 356, 400, 16, "KOSZT PRZEDZIALU TRENINGOW", gui.win, STYLE.meta)
  txt("trng.od.lbl", 10, 374, 290, 14, "z poziomu (%)", gui.win, STYLE.lbl)
  txt("trng.do.lbl", 320, 374, 290, 14, "na poziom (%)", gui.win, STYLE.lbl)
  btn("trng.od.minus", 10, 390, 26, "-", function()
    stan.od = tostring(math.max(0, sanitizujLiczbe(stan.od, MAKS_POZIOM) - 1))
    zapiszStan(); gui.render()
  end)
  pole("trng.od", 40, 390, 90, stan.od, function(t) stan.od = t end)
  btn("trng.od.plus", 134, 390, 26, "+", function()
    stan.od = tostring(math.min(MAKS_POZIOM, sanitizujLiczbe(stan.od, MAKS_POZIOM) + 1))
    zapiszStan(); gui.render()
  end)
  btn("trng.do.minus", 320, 390, 26, "-", function()
    stan.doo = tostring(math.max(0, sanitizujLiczbe(stan.doo, MAKS_POZIOM) - 1))
    zapiszStan(); gui.render()
  end)
  pole("trng.do", 350, 390, 90, stan.doo, function(t) stan.doo = t end)
  btn("trng.do.plus", 444, 390, 26, "+", function()
    stan.doo = tostring(math.min(MAKS_POZIOM, sanitizujLiczbe(stan.doo, MAKS_POZIOM) + 1))
    zapiszStan(); gui.render()
  end)

  -- Wiersz dynamiczny: inna umiejetnosc / cios specjalny
  txt("trng.innaProc.lbl", 10, 422, 200, 14, "procent ceny (1-100)", gui.win, STYLE.lbl)
  pole("trng.innaProc", 10, 438, 90, stan.innaProcent, function(t)
    stan.innaProcent = t
  end)
  txt("trng.innaMax.lbl", 320, 422, 250, 14, "poziom maksymalny (pusty = bez limitu)",
      gui.win, STYLE.lbl)
  pole("trng.innaMax", 320, 438, 90, stan.innaMaxPoziom, function(t)
    stan.innaMaxPoziom = t
  end)
  -- Wynik przedzialu: nominaly + razem + notka
  -- "Razem:" to tylko etykieta rzedu chipow; kwote pokazuja same chipy
  -- (bez duplikatu "1 mdz" pod brazowym paskiem).
  txt("trng.razem", 10, 470, 64, 24, "Razem:", gui.win, STYLE.lbl)
  txt("trng.chip.mth", 82, 470, 120, 24, "", gui.win, STYLE.mth)
  txt("trng.chip.zl", 210, 470, 120, 24, "", gui.win, STYLE.zl)
  txt("trng.chip.sr", 338, 470, 120, 24, "", gui.win, STYLE.sr)
  txt("trng.chip.mz", 466, 470, 120, 24, "", gui.win, STYLE.mz)
  txt("trng.notka", 320, 498, 290, 16, "", gui.win, STYLE.nota)

  -- Stopka: pomoc, tabela, wersja
  btn("trng.pomoc", 10, FOOTER_Y, 80, "Pomoc", function() treningi.onPomoc() end)
  btn("trng.tabela", 98, FOOTER_Y, 80, "Tabela", function() treningi.onTabela() end)
  btn("trng.footer", 300, FOOTER_Y, 310,
      "v" .. PLUGIN_VERSION .. " | " .. PLUGIN_BUILD,
      function() treningi.updaterCheck(true) end, nil, STYLE.footlink)
  local f = gui.managed["trng.footer"]
  if f and type(f.setToolTip) == "function" then
    f:setToolTip("Kliknij, aby sprawdzic aktualizacje")
  end

  gui.odswiez()
end

-- Model empiryczny (Mudlet 5.0.1, sonda na zywym kliencie): dzieci
-- Adjustable.Container laduja w Inside, ktorego y=0 to padding*2 px pod
-- szczytem okna (pasek tytulu, lockStyle standard). Padding 30 daje pasek
-- 60 px - tresc nie nachodzi na tytul (domyslne 10 dawalo tylko 20 px).
-- Wysokosc okna musi pokryc zawartosc + 70 px, inaczej tresc wychodzi
-- poza dolna ramke.
local CONT_PAD  = 30
local INSIDE_TOP = CONT_PAD * 2  -- 60
local WIN_H = 620  -- zawartosc do 538 + INSIDE_TOP + margines 10
local TAB_H = 750  -- konsola 38+628 + INSIDE_TOP + margines

function gui.build()
  if gui.win then return end
  gui.win = Adjustable.Container:new({
    name = "treningi",
    x = 40, y = 40, width = WIN_W, height = WIN_H,
    titleText = "Treningi - kalkulator cen treningow",
    titleTxtColor = "#e6e6f0",
    titleFormat = "lb14",
    padding = CONT_PAD,
    adjLabelstyle = ADJ_STYLE,
    buttonstyle = ADJ_BTN_STYLE,
  })
  -- autoLoad moze wgrac mniejszy rozmiar z poprzedniej wersji: wymus minimum.
  -- Odpornosc na nil: na Mudlet Web get_width/get_height zwraca nil dla
  -- niegotowego kontenera i surowe porownanie przerywalo build (bug E2E
  -- web: pierwsze otwarcie okna padalo cicho, drugie dzialalo).
  pcall(function()
    if (gui.win:get_height() or 0) < WIN_H then gui.win:resize(nil, WIN_H) end
    if (gui.win:get_width() or 0) < WIN_W then gui.win:resize(WIN_W, nil) end
  end)
  gui.win:hide() -- start ukryty (jak zamkniety popup w Dargoth)
  gui.render()
end

function gui.toggle()
  if not gui.win then return end
  if gui.open then
    gui.flushFields() -- zamkniecie splukuje pola: wpis bez Entera nie ginie
    zapiszStan()
    gui.open = false
    if gui.pollTimer then killTimer(gui.pollTimer) gui.pollTimer = nil end
    gui.win:hide()
    return
  end
  gui.open = true
  gui.render()
  gui.win:show()
  -- Mudlet Web: okna nakladaja sie w jednej warstwie; bez raise otwarte
  -- okno moze zostac POD tabela (wyglada jakby komenda nie zadzialala).
  pcall(raiseWindow, "treningi")
  -- Live odczyt pol (filtr + ceny) bez Entera.
  if gui.pollTimer then killTimer(gui.pollTimer) end
  gui.pollTimer = tempTimer(0.4, function() gui.poll() end, true)
end

-- ---------------------------------------------------------------------------
-- Okno tabeli poziomow maksymalnych wg zawodu
-- ---------------------------------------------------------------------------

local TAB_NAME_W = 26
local TAB_CELL_W = 6

local function padRight(s, w)
  s = tostring(s)
  local len = 0
  for _ in s:gmatch("[\1-\127\194-\244][\128-\191]*") do len = len + 1 end
  if len >= w then return s end
  return s .. string.rep(" ", w - len)
end

-- Tabela 1:1 z klientem www/Dargoth: intro, skroty referencyjne, zawod
-- ktory nie oferuje umiejetnosci pokazuje wartosc GP przygaszona, tryb
-- "bez polecenia" dopisuje notke o przyblizeniach. Bez wlasnych legend.
-- Paleta RGB 1:1 z CSS Dargoth: wartosci #c9c9dc, zebra #20203a/#1b1b2e,
-- kolumna GP biala na #31437a, nie-oferuje #8c8ca8. Przyblizenia (tryb bez
-- polecenia) maja ten sam kolor co wartosci dokladne (decyzja ownera:
-- spojne kolory/kontrasty obu trybow, jak w wariancie z poleceniem).
local TC = {
  intro   = "154,154,181",   -- #9a9ab5
  hdrFg   = "185,185,214",   -- #b9b9d6
  hdrBg   = "35,35,58",      -- #23233a
  zebraA  = "32,32,58",      -- #20203a (nieparzyste)
  zebraB  = "27,27,46",      -- #1b1b2e (parzyste)
  nazwa   = "216,216,232",   -- #d8d8e8
  wart    = "232,232,242",   -- #e8e8f2 (wysoki kontrast do przygaszonych)
  przygas = "90,90,120",     -- #5a5a78 (nie oferuje: wyraznie ciemniejsze)
  gpFg    = "255,255,255",
  gpBg    = "49,67,122",     -- #31437a
}

local function tabCell(fg, bg, s)
  gui.tabcon:decho("<" .. fg .. ":" .. bg .. ">" .. padRight(s, TAB_CELL_W))
end

local function renderTabela()
  if not gui.tabcon then return end
  gui.tabcon:clear()
  local pol = gui.tabPolecenie
  gui.tabcon:decho("<" .. TC.intro ..
    ">Poziom maksymalny umiejetnosci w danym zawodzie. 1 trening = 1%.\n\n")
  -- Naglowek (jak thead w Dargoth: tlo #23233a na calej linii)
  gui.tabcon:decho("<" .. TC.hdrFg .. ":" .. TC.hdrBg .. ">" ..
                   padRight("umiejetnosc", TAB_NAME_W))
  for i = 1, #ZAWODY_SKROTY do
    tabCell(TC.hdrFg, TC.hdrBg, ZAWODY_SKROTY[i])
  end
  gui.tabcon:decho("<r>\n")
  for r, w in ipairs(TABELA_POZIOMOW) do
    local zebra = (r % 2 == 1) and TC.zebraA or TC.zebraB
    gui.tabcon:decho("<" .. TC.nazwa .. ":" .. zebra .. ">" ..
                     padRight(w.um, TAB_NAME_W))
    for i = 1, #ZAWODY do
      local lw = limitWyswietlany(w.um, ZAWODY[i], pol)
      if i == #ZAWODY then
        tabCell(TC.gpFg, TC.gpBg, lw and lw.wartosc or "-")   -- kolumna GP
      elseif w.limity[i] < 0 then
        tabCell(TC.przygas, zebra, lw and lw.wartosc or "-") -- nie oferuje
      elseif lw and lw.przyblizona then
        tabCell(TC.wart, zebra, lw.wartosc)  -- przyblizenie: kolor jak dokladne
      else
        tabCell(TC.wart, zebra, lw and lw.wartosc or "-")
      end
    end
    gui.tabcon:decho("<r>\n")
  end
  gui.tabcon:decho("\n<" .. TC.intro ..
    ">Przygaszone = limit jak w GP + ciosy specjalne: "
    .. "75% bez polecenia, 100% z poleceniem.\n")
  if not pol then
    gui.tabcon:decho("<" .. TC.intro ..
      ">Wartosci w tym trybie sa przyblizone "
      .. "(GP + 75% roznicy miedzy zawodem a GP).\n")
  end
end

local function tabBtnRefresh()
  local a = gui.managed["trng.tab.bez"]
  local b = gui.managed["trng.tab.z"]
  if a then applyStyle(a, (not gui.tabPolecenie) and STYLE.primary or STYLE.btn) end
  if b then applyStyle(b, gui.tabPolecenie and STYLE.primary or STYLE.btn) end
end

function gui.buildTabela()
  if gui.tabwin then return end
  gui.tabwin = Adjustable.Container:new({
    name = "treningi_tabela",
    x = 90, y = 30, width = TAB_W, height = TAB_H,
    titleText = "Treningi - poziomy maksymalne wg zawodu",
    titleTxtColor = "#e6e6f0",
    titleFormat = "lb14",
    padding = CONT_PAD,
    adjLabelstyle = ADJ_STYLE,
    buttonstyle = ADJ_BTN_STYLE,
    -- autoLoad wylaczone: :new wgrywalby stan w trakcie budowy, a zapisane
    -- hidden=false robiloby show() = migniecie okna przy pierwszym otwarciu
    -- sesji. Stan wgrywamy jawnie i sanitujemy przed pierwszym pokazaniem.
    autoLoad = false,
  })
  pcall(function() gui.tabwin:load() end)
  -- autoLoad moze wgrac mniejszy rozmiar z poprzedniej wersji: wymus minimum.
  -- Nil-safe jak w gui.build (mudlet-web zwraca nil na niegotowym kontenerze).
  pcall(function()
    if (gui.tabwin:get_height() or 0) < TAB_H then gui.tabwin:resize(nil, TAB_H) end
    if (gui.tabwin:get_width() or 0) < TAB_W then gui.tabwin:resize(TAB_W, nil) end
  end)
  btn("trng.tab.z", 10, 4, 200, "z poleceniem", function()
    gui.tabPolecenie = true
    tabBtnRefresh(); renderTabela()
  end, gui.tabwin)
  btn("trng.tab.bez", 218, 4, 200, "bez polecenia", function()
    gui.tabPolecenie = false
    tabBtnRefresh(); renderTabela()
  end, gui.tabwin)
  gui.tabcon = Geyser.MiniConsole:new({
    -- 32 linie tabeli (tryb bez polecenia) * ~19 px/linia (Mudlet 5.0.1,
    -- fontSize 9) = 608 px; wiersz = 102 znaki * ~7.8 px = ~796 px.
    -- Wysokosc okna = konsola + INSIDE_TOP + marginesy (model empiryczny).
    name = "trng.tabcon", x = 10, y = 38, width = 840, height = 628,
    wrapAt = TAB_NAME_W + #ZAWODY * TAB_CELL_W + 2,
  }, gui.tabwin)
  pcall(function() gui.tabcon:setFont("Monospace") end)
  pcall(function() gui.tabcon:setFontSize(9) end)
  pcall(function() gui.tabcon:setBgColor(22, 22, 30) end) -- #16161e jak okno
  tabBtnRefresh()
  renderTabela()
  gui.tabwin:hide()
end

function gui.toggleTabela()
  gui.buildTabela()
  -- Jedno zrodlo prawdy o widocznosci: tabwin.hidden. Geyser utrzymuje je
  -- na kazdej sciezce (show/hide, krzyzyk X -> hideObj, minimalizacja,
  -- load), wiec zadna akcja usera na oknie nie rozsynchronizuje toggle'a.
  -- Dawna wlasna flaga otwarcia po zamknieciu X mowila "otwarte" na ukrytym
  -- oknie i pierwszy klik tylko ja resetowal (bug "dwa kliki", desk. + web).
  -- Zminimalizowany pasek tytulu (hidden=false, minimized=true) traktujemy
  -- jako zamkniete -> otwarcie przez restore.
  local otwarte = gui.tabwin.hidden == false and not gui.tabwin.minimized
  if otwarte then
    gui.tabwin:hide()
    return
  end
  pcall(function()
    if gui.tabwin.minimized then gui.tabwin:restore() end
  end)
  renderTabela()
  gui.tabwin:show()
  pcall(function()
    if gui.tabwin.Inside then gui.tabwin.Inside:show() end
  end)
  pcall(raiseWindow, "treningi_tabela")
end

-- ==========================================================================
-- AKTUALIZATOR (wzorzec kalendarzy: auto-check throttled 8 h, reczna
-- instalacja komenda; stale nazwy assetow, sprzatanie historycznych nazw)
-- ==========================================================================

local C_HEADER = "<yellow>"
local C_NOW    = "<green>"
local C_RESET  = "<reset>"

local function safeCecho(s)
  if cecho then cecho(s) else io.write((s:gsub("<%a+>", ""))) end
end

local UPDATE_REPO         = "arkadia-mudlet-treningi"
local UPDATE_PKG_NAME     = "treningi"
local UPDATE_CMD          = "/treningi aktualizuj"
local UPDATE_THROTTLE_SEC = 8 * 3600
local UPDATE_API_URL      = "https://api.github.com/repos/Isithunzi000/" .. UPDATE_REPO .. "/releases/latest"
local UPDATE_CACHE_PATH   = getMudletHomeDir() .. "/treningi_update_cache.lua"
-- Historyczne nazwy paczek na mudlet-web (tozsamosc = nazwa pliku):
-- dawniej <pkg>_update; self = kamizelka na lokalne buildy.
local UPDATE_LEGACY_PKGS = {
  "treningi_update",
  "treningi_" .. PLUGIN_VERSION:gsub("%.", "_"),
}

local updateDlHandlers = {}
local updateMetaPath = nil
local updatePkgPath = nil
local updatePendingVersion = nil
local updateManual = false

local function updateCacheRead()
  -- table.load bez tabeli docelowej zwraca nil (Mudlet 5.0.1) - patrz
  -- komentarz w wczytajStan.
  local t = {}
  local ok = pcall(table.load, UPDATE_CACHE_PATH, t)
  if ok then
    if type(t[1]) == "table" and t.lastCheck == nil then t = t[1] end
    return t
  end
  return {}
end

local function updateCacheWrite(latest)
  pcall(table.save, UPDATE_CACHE_PATH, { lastCheck = os.time(), knownLatest = latest })
end

local function updateVersionParts(v)
  local parts = {}
  for seg in tostring(v):gmatch("[^%.]+") do
    parts[#parts + 1] = tonumber(seg:match("^%d+")) or 0
  end
  return parts
end

-- Porownanie numeryczne segmentow (suffix literowy pomijany): 1.0.9m < 1.0.16m.
local function updateVersionNewer(a, b)
  local pa, pb = updateVersionParts(a), updateVersionParts(b)
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return x > y end
  end
  return false
end

local function updateSay(msg)
  safeCecho(C_HEADER .. "[treningi] " .. msg .. C_RESET .. "\n")
end

local function updateNotify(latest)
  safeCecho("\n" .. C_HEADER .. "[treningi] Dostepna nowa wersja " .. latest ..
    " (masz " .. PLUGIN_VERSION .. "). Wpisz " .. C_NOW .. UPDATE_CMD ..
    C_RESET .. C_HEADER .. " aby zaktualizowac." .. C_RESET .. "\n\n")
end

local function updateFail(what)
  updateSay("Nie udalo sie " .. what .. " - sprobuj pozniej.")
end

local function updateKillHandlers()
  for k, id in pairs(updateDlHandlers) do
    killAnonymousEventHandler(id)
    updateDlHandlers[k] = nil
  end
end

local function updateOnError(event)
  updateKillHandlers()
  updateMetaPath = nil
  updatePkgPath = nil
  updatePendingVersion = nil
  updateFail("sprawdzic aktualizacji")
end

local function updateOnPkgDone(event, path)
  if path ~= updatePkgPath then return end
  updateKillHandlers()
  local v = updatePendingVersion
  updatePkgPath = nil
  updatePendingVersion = nil
  pcall(uninstallPackage, UPDATE_PKG_NAME)
  for _, legacyName in ipairs(UPDATE_LEGACY_PKGS) do
    pcall(uninstallPackage, legacyName)
  end
  tempTimer(1, function()
    installPackage(path)
    os.remove(path)
    updateSay("Zaktualizowano do wersji " .. v .. ". Zrestartuj Mudleta, aby zmiany zadzialaly.")
  end)
end

local function updateOnMetaDone(event, path)
  if path ~= updateMetaPath then return end
  updateMetaPath = nil
  if updateDlHandlers.meta then
    killAnonymousEventHandler(updateDlHandlers.meta)
    updateDlHandlers.meta = nil
  end
  local ok, meta = pcall(function()
    local f = io.open(path, "r")
    if not f then error("brak pliku metadanych") end
    local body = f:read("*a")
    f:close()
    return yajl.to_value(body)
  end)
  if not ok or type(meta) ~= "table" or type(meta.tag_name) ~= "string" then
    updateKillHandlers()
    updateFail("sprawdzic aktualizacji")
    return
  end
  local latest = meta.tag_name:gsub("^v", "")
  updateCacheWrite(latest)
  if not updateVersionNewer(latest, PLUGIN_VERSION) then
    updateKillHandlers()
    if updateManual then updateSay("Masz najnowsza wersje (" .. PLUGIN_VERSION .. ").") end
    return
  end
  if not updateManual then
    updateKillHandlers()
    updateNotify(latest)
    return
  end
  local url = nil
  if type(meta.assets) == "table" then
    for _, a in ipairs(meta.assets) do
      if type(a) == "table" and type(a.browser_download_url) == "string"
         and a.browser_download_url:match("%.mpackage$") then
        url = a.browser_download_url
        break
      end
    end
  end
  if not url then
    url = "https://github.com/Isithunzi000/" .. UPDATE_REPO .. "/releases/download/v" ..
          latest .. "/" .. UPDATE_PKG_NAME .. ".mpackage"
  end
  updatePendingVersion = latest
  updatePkgPath = getMudletHomeDir() .. "/" .. UPDATE_PKG_NAME .. ".mpackage"
  updateDlHandlers.pkg = registerAnonymousEventHandler("sysDownloadDone", updateOnPkgDone)
  downloadFile(updatePkgPath, url)
end

local function startUpdateCheck(manual)
  updateManual = manual and true or false
  if mudletOlderThan and mudletOlderThan(4, 6) then
    if updateManual then updateSay("Aktualizator wymaga Mudleta 4.6 lub nowszego.") end
    return
  end
  if not updateManual then
    local cache = updateCacheRead()
    local lastCheck = tonumber(cache.lastCheck) or 0
    if os.time() - lastCheck < UPDATE_THROTTLE_SEC then
      if type(cache.knownLatest) == "string"
         and updateVersionNewer(cache.knownLatest, PLUGIN_VERSION) then
        updateNotify(cache.knownLatest)
      end
      return
    end
  end
  updateMetaPath = getMudletHomeDir() .. "/" .. UPDATE_PKG_NAME .. "_update_meta.json"
  updateDlHandlers.meta = registerAnonymousEventHandler("sysDownloadDone", updateOnMetaDone)
  updateDlHandlers.err  = registerAnonymousEventHandler("sysDownloadError", updateOnError)
  downloadFile(updateMetaPath, UPDATE_API_URL)
end

function treningi.updaterCheck(manual)
  startUpdateCheck(manual)
end

-- ==========================================================================
-- POMOC (konsola), ALIASY, INIT
-- ==========================================================================

function treningi.banner()
  return "Treningi " .. PLUGIN_VERSION .. " (build " .. PLUGIN_BUILD ..
         ") - kalkulator cen treningow."
end

function treningi.onPomoc()
  cecho("\n<green>" .. treningi.banner() .. "<reset>\n")
  cecho("<yellow>Aliasy:<reset>\n")
  cecho("  <yellow>/treningi<reset> - otwiera/zamyka okno kalkulatora\n")
  cecho("  <yellow>/treningi pomoc<reset> (albo <yellow>/treningi help<reset>) - ten tekst\n")
  cecho("  <yellow>/treningi tabela<reset> - okno poziomow maksymalnych wg zawodu\n")
  cecho("  <yellow>/treningi aktualizuj<reset> - sprawdza i pobiera nowa wersje\n")
  cecho("<yellow>Jak liczyc:<reset>\n")
  cecho("  1. Wybierz umiejetnosc z listy (filtr nad lista zawija liste).\n")
  cecho("  2. Wpisz koszt treningu z gry (zloto/srebro/miedz) - kalkulator\n")
  cecho("     pokaze obecny poziom. Przelacznik pod polami wybiera, czy podany\n")
  cecho("     koszt dotyczy ostatniego czy nastepnego treningu.\n")
  cecho("  3. Pola 'z poziomu / na poziom' licza laczny koszt przedzialu\n")
  cecho("     (wlacznie). Kolejnosc wpisow nie ma znaczenia.\n")
  cecho("  <yellow>cios specjalny<reset> - umiejetnosc specjalna z zawodu: cena\n")
  cecho("     zawsze 100% tabeli; maks. 75%.\n")
  cecho("  <yellow>inna umiejetnosc...<reset> - wlasny procent ceny (1-100)\n")
  cecho("     i opcjonalny poziom maksymalny (puste pole = bez limitu).\n")
  cecho("Wszystkie pola zapisuja sie na dysku profilu i wracaja po restarcie.\n")
  cecho("Plugin w pelni zgodny z regulaminem gry - czysty kalkulator,\n")
  cecho("zero automatyki, zero wysylania komend.\n\n")
end

function treningi.onAlias()
  gui.toggle()
end

function treningi.onTabela()
  gui.toggleTabela()
end

function treningi.onAktualizuj()
  startUpdateCheck(true)
end

-- init: stan z dysku profilu, okno, auto-check aktualizacji (throttled 8 h)
wczytajStan()
gui.build()
if type(tempTimer) == "function" then
  tempTimer(10, function() startUpdateCheck(false) end)
end
if cecho then
  cecho("<green>[treningi]<reset> Kalkulator cen treningow v" .. PLUGIN_VERSION ..
        " zaladowany. Wpisz <yellow>/treningi<reset> (pomoc: <yellow>/treningi pomoc<reset>).\n")
end

-- Hooki dla lokalnych testow silnika (port harnessa Dargoth).
treningi._test = {
  cenaTreningu      = cenaTreningu,
  obecnyPoziom      = obecnyPoziom,
  kosztPrzedzialu   = kosztPrzedzialu,
  naMiedz           = naMiedz,
  zMiedzi           = zMiedzi,
  sanitizujLiczbe   = sanitizujLiczbe,
  limitZWpisu       = limitZWpisu,
  porzadkujPrzedzial= porzadkujPrzedzial,
  formatujLiczbe    = formatujLiczbe,
  limitDla          = limitDla,
  limitWyswietlany  = limitWyswietlany,
  UMIEJETNOSCI      = UMIEJETNOSCI,
  ZAWODY            = ZAWODY,
  TABELA_POZIOMOW   = TABELA_POZIOMOW,
  wczytajStan       = wczytajStan,
  stan              = stan,
  KOSZT_BAZOWY      = KOSZT_BAZOWY,
}

end
