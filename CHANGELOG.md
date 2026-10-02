# Změny

Verze aplikace je v souboru `VERSION` a zvyšuje se s každou změnou.
Číslo sestavení iOS aplikace (build) přiděluje GitHub Actions.

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
