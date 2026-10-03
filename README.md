# ponk for Bauhaus

Neoficiální open-source aplikace pro nabídku **bauhaus.cz**: celý katalog, historie cen,
skutečné slevy, skladovost na prodejnách včetně čísla regálu a hlídání cen.
Webová verze běží na tvém počítači. iOS appka počítač nepotřebuje, denní data jí připravuje GitHub Actions zdarma.

> Ponk není nijak spojený se společností BAUHAUS. Názvy, ceny a obrázky patří jejich vlastníkům.
> Aplikace čte stejná veřejná data, jaká vidí každý návštěvník webu, a dělá to šetrně
> (jeden dotaz najednou, pauza mezi dotazy).

## Co umí

- Celý katalog (~94 000 produktů) s cenami, 30denním minimem, štítky a parametry
- Denní kontrola cen v nastavený čas a historie každé změny (graf v detailu)
- **Skutečná sleva** počítaná proti nejnižší ceně za 30 dní, ne proti „původní“ ceně
- Hodnocení zákazníků (0–5 hvězdiček) a recenze ze všech webů BAUHAUS, zahraniční přeložené do češtiny
- Skladovost na všech 9 prodejnách a **regál + pole**, kde zboží leží
- Filtry: kategorie, cena, značka, sleva, zlevněno za X dní, skladem na prodejně / online,
  štítky (výprodej, doprava zdarma…), hodnocení, cena za jednotku, parametry podle kategorie
- Řazení mimo jiné podle skutečné slevy, posledního zlevnění a ceny za jednotku (Kč/m², Kč/kg)
- Hlídání cen produktů (i s cílovou cenou) a uložená hledání s počtem novinek
- **Katalog**: všechny položky na jedné stránce s hledáním, rychlými filtry a čtečkou čárových kódů (iOS)
- Naposledy hledané a prohlížené, rychlé hlídání podržením dlaždice, fotky s přiblížením (iOS)
- Světlý / tmavý vzhled podle systému nebo ručně, pět open-source písem na výběr

## Spuštění (Windows)

1. Nainstaluj **Python 3.9 nebo novější** z [python.org](https://www.python.org/downloads/)
   a při instalaci zaškrtni **Add python.exe to PATH**. Nic dalšího se instalovat nemusí.
2. Rozbal Ponk třeba do `C:\Ponk` a spusť **start.bat**.
3. Windows se zeptá na firewall: povol **soukromé sítě** (jinak se mobil nepřipojí).
4. V prohlížeči otevři `http://localhost:8765`. Poprvé se stahuje celý katalog,
   trvá to zhruba 30–40 minut (podle rychlosti připojení), aplikace se mezitím plní.
5. V okně serveru je adresa pro mobil, např. `http://192.168.1.20:8765`.
   Otevři ji v Safari a dej **Sdílet → Přidat na plochu**.

### Aby se Ponk spouštěl sám
Stiskni `Win + R`, napiš `shell:startup` a do otevřené složky dej zástupce na `start.bat`.
Denní kontrola proběhne v nastavený čas (výchozí 6:00). Když počítač v tu dobu neběží,
proběhne hned po zapnutí.

### Linux / macOS
```bash
./start.sh            # nebo: python3 run.py
python3 run.py sync   # jednorázová kontrola cen bez serveru
```

## iOS aplikace (bez počítače)

Nativní appka ve SwiftUI pro iOS 18 a novější, na iOS 26 s Liquid Glass. Počítač nepotřebuje:
ceny celého katalogu každé ráno kontroluje GitHub Actions (`.github/workflows/data.yml`)
a zveřejní štíhlou databázi (~5 MB) ve vydání **data**. Telefon si ji stáhne, hledá a filtruje
lokálně (funguje i offline) a detail produktu načítá živě z Bauhausu. Hlídané produkty
a uložená hledání zůstávají jen v telefonu.

Appka se sestaví zdarma v GitHub Actions (`ios.yml`) a instaluje se jako `.ipa`
(Feather, Sideloadly…). Postup: [docs/ios.md](docs/ios.md).

Chceš vlastní kopii? Forkni repozitář, v záložce Actions povol workflow a spusť
„Data (denní kontrola cen)“. V aplikaci pak ve Více nastav svůj repozitář jako zdroj dat.

## Jak je to postavené

```
run.py               spuštění serveru / jednorázové synchronizace
ponk/bauhaus.py      klient veřejného API bauhaus.cz (Vue Storefront + Elasticsearch)
ponk/sync.py         stažení katalogu, historie cen, skladovost po prodejnách
ponk/search.py       vyhledávání, filtry, fasety, detail produktu
ponk/server.py       lokální HTTP server (REST API + web) a plánovač denní kontroly
web/                 webová aplikace bez build kroku (HTML, CSS, JS) + písma
tools/make_icons.py  ikony aplikace s logem Bauhaus (iOS + web)
ios/                 SwiftUI aplikace (projekt generuje XcodeGen)
data/                databáze SQLite (vzniká při prvním spuštění, není v gitu)
```

Server používá jen standardní knihovnu Pythonu. Data jsou v `data/ponk.sqlite3`;
pro zálohu stačí zkopírovat složku `data`.

Nastavení přes proměnné prostředí: `PONK_PORT` (výchozí 8765), `PONK_HOST`,
`PONK_DATA` (složka s databází), `PONK_NO_SCHEDULER=1` (vypne automatickou kontrolu).

## Licence

Kód: MIT (soubor `LICENSE`). Písma Barlow, Sofia Sans, Encode Sans, Fira Sans a Saira:
SIL Open Font License 1.1 (licence přiloženy u souborů písem).
