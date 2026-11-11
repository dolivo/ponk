# Změny

Verze aplikace je v souboru `VERSION` a zvyšuje se s každou změnou.
Číslo sestavení iOS aplikace (build) přiděluje GitHub Actions.

## 0.15.0
- Přechod mezi záložkami bez poskakování: obrazovka i horní lišta se jen rychle prolnou a pohyb
  obstarají položky. Dlaždice, řádky, kategorie a položky seznamu při otevření záložky pružně
  vyskočí jedna po druhé, shora dolů a zleva doprava. Při posouvání se nic neanimuje;
  při zapnutém Omezení pohybu v iOS se položky jen zobrazí.

## 0.14.0
- Animované přechody mezi záložkami Katalog, Slevy, Seznam, Hledat a Více. S bočním menu
  nová obrazovka vyplave ve směru pohybu v menu (dolů v menu = zespodu, nahoru = shora)
  a stará se zmenší a rozmaže do pozadí, vše na pružině. Se spodní lištou obsah záložky
  při přepnutí vyjede a zaostří se. Při zapnutém Omezení pohybu v iOS jen jemné prolnutí.

## 0.13.3
- Oprava: v užším nákupním seznamu se cena lámala po písmenech a štítek regálu do dvou řádků.
  Cena je teď vedle množství, a když se nevejde, pod ním; regál a sklad se případně dají pod sebe.

## 0.13.2
- Oprava: v nákupním seznamu a hlídaných zasahovalo boční menu do položek (cena, tlačítko Smazat
  po přejetí prstem). Seznam se teď u bočního menu zúží, takže je všechno vedle menu a klikatelné.

## 0.13.1
- Když vyjede klávesnice, boční menu pružně přejede nahoru (pod horní lištu), aby nebylo schované
  pod klávesnicí a šlo na něj klepat. Po schování klávesnice se vrátí zpět dolů.

## 0.13.0
- Boční menu má animace jako systémová lišta iOS: zvýraznění vybrané záložky pružně přejede
  na novou, ikona se při klepnutí zhoupne a vyplní, tlačítko se při stisku zmáčkne, odznak
  zlevněných se plynule přepočítá, menu při spuštění vyjede od okraje a při přepnutí strany
  ve Více přejede na druhý okraj. Obrazovky se při přepnutí jemně prolnou.
- Druhé klepnutí na Hledat (v bočním menu i ve spodní liště) vrátí hledání na začátek
  a rovnou otevře pole hledání s klávesnicí.
- Oprava: kategorie nad názvem produktu se při zalomení do dvou řádků překrývaly s názvem.

## 0.12.0
- **Akce výrobců a dárky k nákupu** z webu Bauhausu (např. Ryobi: startovací sada zdarma k nářadí
  ONE+ při nákupu na prodejně). V detailu produktu hned pod cenou je karta akce v barvách výrobce:
  co dostanete zdarma a v jaké hodnotě, „Jen na prodejně“, do kdy akce platí a odkaz na podmínky.
  Rozpoznává dárky, cashback, soutěže a akce typu 2+1; prošlé akce se nezobrazují.
- Na dlaždicích štítek „Dárek k nákupu“ / „Akce výrobce“, rychlý filtr „Dárek k nákupu“ v katalogu
  a na úvodní stránce sekce „Dárky k nákupu“ a „Akce výrobců: cashback a soutěže“.
- Další údaje z webu Bauhausu v detailu: množstevní sleva (cena za kus od N kusů), prodloužená
  záruka BAUHAUS, Exkluzivně v BAUHAUS, montážní servis, půjčovna, energetická třída, obsah balení,
  dokumenty a návody (PDF), související produkty a příslušenství, podobné produkty, produkty ze
  stejné série, výrobce/dovozce a bezpečnostní upozornění u chemie.
- Totéž ve webové aplikaci. Data mají schéma 4 (starší verze aplikace je dál načtou, jen bez novinek).

## 0.11.0
- **Menu pro jednu ruku**: hlavní menu je svisle u pravého okraje obrazovky ve spodní části,
  kam dosáhne palec (skleněný panel, na iOS 26 Liquid Glass). Ve Více → Umístění menu jde přepnout
  na levou stranu nebo zpět na klasickou spodní lištu.
- V bočním menu si záložky drží stav (rozscrollovaný seznam, otevřený detail); opětovné klepnutí
  na otevřenou záložku ji vrátí na začátek. Odznak zlevněných hlídaných zůstává u Seznamu.

## 0.10.0
- Nákupní seznamy (záložka Seznam, vedle nich Hlídané):
  - víc pojmenovaných seznamů (např. „Dřevník“), přejmenování, mazání,
  - přidání z detailu produktu (s množstvím a volbou seznamu) nebo podržením dlaždice, i vlastní text,
  - řazení po cestě prodejnou podle čísla regálu a pole (živě z Bauhausu), regál u každé položky,
  - sklad na zvolené prodejně, „skladem X z Y“ a tip na prodejnu, která má skladem víc,
  - součet ceny, změna ceny od přidání, odškrtávání do košíku (klepnutím nebo přejetím),
  - mapa trasy: plánek prodejny s očíslovanými zastávkami,
  - sdílení seznamu jako text, poznámky k položkám.
- Detail produktu: tlačítko „Do seznamu“ a informace, ve kterém seznamu produkt už je.

## 0.9.0
- Detail produktu: kategorie nad názvem jdou rozkliknout. Hlavní kategorie a podkategorie otevřou
  přehled podkategorií, poslední úroveň rovnou produkty v kategorii.

## 0.8.1
- Oprava: po návratu z detailu produktu se seznam načítal znovu od první stránky, takže chvíli
  zůstala prázdná obrazovka a pak skočil na úplně jiné místo. Výsledky, úvod i kategorie se teď
  při návratu nepřenačítají a seznam si drží pozici podle produktu nahoře.
- Stránkování má stabilní pořadí (u shodné ceny, slevy apod. rozhoduje kód produktu), stejný
  produkt se v seznamu nemůže objevit dvakrát.

## 0.8.0
- Vyhledávání podle klíčových slov: hledá se i v parametrech produktů (např. „li-ion 18 v“, „dub“).
- Oprava překlepů: „sroubvak“ najde šroubováky, „vrtcka makta“ vrtačky Makita, „dlaždyce“ dlaždice.
  Funguje i bez diakritiky a pro začátek slova. Nahoře se ukáže „Zobrazuji výsledky pro …“
  s možností hledat přesně, v našeptávači „Myslel jsi …?“. Když žádný produkt neobsahuje všechna
  slova, ukážou se ty s nejvíce shodami. Slovník připravuje denní úloha na GitHubu (tabulka vocab).
- Detail produktu: kopírování názvu, kódu, EAN, popisu, parametrů, odkazu nebo všeho najednou
  (tlačítko v horní liště, podržení na názvu či parametru, popis jde označit).

## 0.7.0
- **Hodnocení zákazníků**: 0–5 hvězdiček (i poloviční) s průměrem a počtem recenzí u každého produktu
  ve výsledcích hledání, v regálech i v detailu. Bez recenzí jsou hvězdičky prázdné „(0)“.
  Filtr „Hodnocení 4+“ a řazení „Nejlépe hodnocené“ teď používají skutečné recenze.
- **Recenze v detailu produktu**: souhrn (průměr, rozložení 5–1 hvězdiček) a texty recenzí
  se jménem, datem, „ověřený nákup“ a odpověďmi BAUHAUS. Recenze sdílí všechny weby BAUHAUS
  (Česko, Německo, Rakousko, Švýcarsko…); zahraniční jsou přeložené do češtiny a jde zobrazit originál.
  Načítají se živě z bauhaus.cz (iOS i web).
- Denní úloha stahuje hodnocení z API recenzí BAUHAUS (vaimo-reviews, 50 produktů na dotaz);
  každý den třetinu katalogu, nové produkty hned. Nastavení `sync_ratings`.

## 0.6.2
- Štítek sell_off se zase jmenuje „Výprodej“ (zpět z „Doprodej“). Pořadí filtrů zůstává.

## 0.6.1
- Oprava: logo Bauhausu se v aplikaci nezobrazovalo (v liště ani v animaci bylo jen „ponk“).
  Logo má teď pevný poměr stran a je jako ostrý PNG ve 3× rozlišení.
- Úvodní animace běží na plné obnovovací frekvenci displeje (ProMotion 120 Hz,
  CADisableMinimumFrameDurationOnPhone), začne až po vykreslení rozhraní a animuje jednu vrstvu.
- Štítek „Výprodej“ se teď jmenuje **Doprodej**, stejně jako na bauhaus.cz (je to tentýž štítek
  sell_off – samostatný „doprodej“ Bauhaus nemá). Filtr, rychlé filtry, dlaždice i web.
- Filtry: Nabídka (Doprodej, Akce, Doprava zdarma…) je úplně nahoře, Kategorie úplně dole (iOS i web).

## 0.6.0
- Úvodní animace po spuštění (~1,5 s): logo pružně naskočí, pod ním „ponk“, pak se plynule
  rozplyne do aplikace. Navazuje na launch screen ve stejné barvě pozadí (colorset LaunchBackground).
  S Omezit pohyb jen krátké prolnutí.
- Logo vlevo v horní liště (logo Bauhaus + „ponk“) na záložkách Katalog, Slevy, Hlídané a Hledat,
  místo textového titulku; na iOS 26 bez skleněného podkladu. Na záložce Více zůstává titulek.
- Originální logo Bauhausu (domečky + BAUHAUS, vektor z bauhaus.cz) v liště, úvodní animaci,
  hlavičkách a na webu místo dřívější napodobeniny. V iOS jako vektorové PDF v Assets („BauhausLogo“).
- Ikona aplikace (světlá, tmavá, tónovaná) i webové ikony s originálním logem Bauhausu.
- Čtečka čárových kódů v Katalogu je vpravo v liště (vlevo je logo).

## 0.5.1
- Ikona aplikace ve třech variantách pro iOS 18+: světlá, tmavá (průhledný podklad) a tónovaná
  (bílé tvary s vyříznutým nápisem, v tónovaném režimu dobře čitelná). Generuje tools/make_icons.py.
- Mapy prodejen: čísla regálů doplněna pro další prodejny (data přes GitHub, bez aktualizace aplikace).

## 0.5.0
- Mapa prodejny: v detailu produktu u každé prodejny „Ukázat na mapě prodejny“ – oficiální plánek
  Bauhausu přiblížený na regál, zvýrazněná sekce. Čísla regálů zatím pro Brno Ivanovice a Brno Heršpická
  (ponk/storemaps.json, nástroj tools/build_store_maps.py), ostatní prodejny zobrazí plánek bez zvýraznění.
- Nově naskladněno: denní úloha porovnává sklad se včerejškem (prodejny i e-shop). Filtr „Nově naskladněno“,
  sekce „Nově skladem“ pro tvoji prodejnu a upozornění, když je hlídaný produkt znovu skladem.
- Nově v nabídce: štítek „Novinka“ (14 dní), filtr „Nově v nabídce“ a řazení „Naposledy přidané“.
- Produkty stažené z nabídky zůstávají 30 dní v datech, hlídané tak nezmizí (ukážou „Není v nabídce“).
- Sekce na úvodní stránce určuje ponk/home_sections.json na GitHubu – nové jdou přidat bez aktualizace aplikace.
- Sloučeno s 0.4.0 (Katalog, čtečka EAN, mezipaměť obrázků, logo).

## 0.4.0 – ponk for Bauhaus
- Nový název **ponk for Bauhaus**, logo Bauhaus v aplikaci (úvod, Více) i v ikoně na ploše
  (iOS i web). Ikony se generují skriptem `tools/make_icons.py`.
- **Katalog** jako hlavní stránka: všechny položky najednou, hledání přímo v seznamu,
  rychlé filtry (Výprodej, Skladem na mé prodejně, Skladem online, Sleva 30 %+, Zlevněno za 7 dní)
  a k tomu všechny dosavadní filtry a řazení. Na webu záložka Katalog.
- Liquid Glass: jemný přechod v barvě stránky pod horní lištou, spodní lištou a plovoucími
  tlačítky – text a ikony na skle jsou čitelné i nad fotkami. Tlačítka na skle mají text v barvě písma.
- iOS – pohodlí: čtečka čárových kódů (EAN) v Katalogu, poslední hledání, naposledy prohlížené
  produkty na stránce Slevy, podržení dlaždice → Hlídat cenu / Kopírovat název / kód,
  fotky produktu na celou obrazovku s přiblížením, kód a EAN jde zkopírovat, haptická odezva,
  pull-to-refresh ve výsledcích, aplikace si pamatuje poslední záložku.
- iOS – rychlost: obrázky v mezipaměti (paměť + 512 MB disk) a dekódované mimo hlavní vlákno
  v plném rozlišení, znovupoužívané SQL dotazy, počty pro filtry se počítají jen při otevřených
  filtrech, štítky jedním dotazem místo sedmi, našeptávač bez opakovaného procházení kategorií
  a značek, rychlejší příprava stažených dat (jeden připravený příkaz pro 94 000 řádků).
- Záložka Výprodej je nově rychlý filtr v Katalogu a odkaz na stránce Slevy (dřív Domů).

## 0.3.0
- iPhone už nepotřebuje počítač. Ceny celého katalogu každé ráno kontroluje GitHub Actions
  (`.github/workflows/data.yml`) a zveřejní štíhlou databázi (~5 MB) ve vydání „data“.
- Aplikace si data stáhne sama (po otevření nebo na pozadí, výchozí jen na Wi-Fi),
  hledá a filtruje přímo v telefonu a funguje i offline.
- Detail produktu načítá živě z Bauhausu aktuální cenu, sklad, regál, fotky a popis.
- Upozornění, když hlídaný produkt zlevní nebo klesne na cílovou cenu.
- Hlídané produkty a uložená hledání zůstávají jen v telefonu.

## 0.2.0
- iOS: oprava instalace přes Feather/ESign. Podepisovač v iPhonu musel binárce
  zvětšit místo na podpis a přitom jí odebral příznak „spustitelný“, takže iOS
  aplikaci odmítl. Sestavení teď místo na podpis rezervuje předem.
- iOS: podpora iOS 18 a novějších (Liquid Glass jen na iOS 26+).
- Číslo verze je vidět v sekci Více (web i iOS).
- Web: odkaz „Zobrazit vše“ u hlídaných produktů, e-shop „0 ks“ → „není“.

## 0.1.0
- První verze: server se scraperem a historií cen, webová aplikace, iOS aplikace.
