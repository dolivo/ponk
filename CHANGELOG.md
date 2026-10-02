# Změny

Verze aplikace je v souboru `VERSION` a zvyšuje se s každou změnou.
Číslo sestavení iOS aplikace (build) přiděluje GitHub Actions.

## 0.2.0
- iOS: oprava instalace přes Feather/ESign. Podepisovač v iPhonu musel binárce
  zvětšit místo na podpis a přitom jí odebral příznak „spustitelný“, takže iOS
  aplikaci odmítl. Sestavení teď místo na podpis rezervuje předem.
- iOS: podpora iOS 18 a novějších (Liquid Glass jen na iOS 26+).
- Číslo verze je vidět v sekci Více (web i iOS).
- Web: odkaz „Zobrazit vše“ u hlídaných produktů, e-shop „0 ks“ → „není“.

## 0.1.0
- První verze: server se scraperem a historií cen, webová aplikace, iOS aplikace.
