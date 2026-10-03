# Změny

Verze aplikace je v souboru `VERSION` a zvyšuje se s každou změnou.
Číslo sestavení iOS aplikace (build) přiděluje GitHub Actions.

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
