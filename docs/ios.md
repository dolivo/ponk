# iOS aplikace bez Macu

Appka se sestaví na Macu v cloudu GitHubu (jen kompilace, data zůstávají u tebe)
a do iPhonu ji nahraješ z Windows. Potřebuješ iPhone s **iOS 18 nebo novějším**
(iPhone XS a novější). Liquid Glass se zapne na iOS 26, na starších verzích má appka klasický vzhled. Potřebuješ i bezplatné Apple ID.

## 1. Sestavení v GitHub Actions (jednou, pak po každé změně kódu)

1. Založ si účet na [github.com](https://github.com) a nový **veřejný** repozitář `ponk`
   (u veřejných repozitářů je sestavení na Macu zdarma).
2. Nahraj do něj celý projekt. Nejjednodušší je [GitHub Desktop](https://desktop.github.com):
   *File → Add local repository* → složka Ponk → *Publish repository*.
   (Při nahrávání přes web se může vynechat skrytá složka `.github`, ve které je sestavení.)
3. Na GitHubu otevři záložku **Actions → iOS build**. Sestavení se spustí samo,
   případně klikni na *Run workflow*. Trvá asi 5–10 minut.
4. Po dokončení dole v sekci **Artifacts** stáhni `Ponk-ipa` a rozbal z něj `Ponk.ipa`.

Když sestavení skončí chybou, stáhni artefakt `xcodebuild-log` a pošli ho Claudovi.

## 2. Instalace do iPhonu (Windows)

1. Nainstaluj **iTunes** a **iCloud** z webu Applu (ne verze z Microsoft Store),
   potom [Sideloadly](https://sideloadly.io).
2. Připoj iPhone kabelem a na telefonu potvrď *Důvěřovat tomuto počítači*.
3. Přetáhni `Ponk.ipa` do Sideloadly, zadej Apple ID a klikni **Start**.
4. Na iPhonu zapni **Nastavení → Soukromí a zabezpečení → Režim vývojáře** (telefon se restartuje).
5. **Nastavení → Obecné → Správa VPN a zařízení** → tvoje Apple ID → *Důvěřovat*.
6. Otevři Ponk a zadej adresu serveru, kterou vypisuje `start.bat`
   (řádek „v mobilu (Wi-Fi)“). Potvrď dotaz na přístup k místní síti.

## Omezení bezplatného Apple ID

- Podpis platí **7 dní**, pak appku v Sideloadly znovu nahraj (data v ní zůstanou).
  Sideloadly umí podpis obnovovat automaticky, když běží na počítači ve stejné Wi-Fi.
- Najednou mohou být takto nainstalované nejvýš 3 aplikace.
- Mimo domácí Wi-Fi appka ukazuje poslední stažená data s upozorněním „Offline“.
