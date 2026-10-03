#!/usr/bin/env python3
"""Z map prodejen Bauhausu vytáhne čísla regálů a jejich polohu.

Bauhaus má pro každou prodejnu plánek (CMS blok product_finder_<kód>), kde jsou
čísla regálů v červených rámečcích, např. "426" nebo rozsah "142-162". Skript
najde rámečky, přečte čísla (tesseract) a ke každému určí barevnou zónu, ve které
leží. Automatické čtení čísel z JPEG plánků je nespolehlivé, proto se výsledek musí ručně
zkontrolovat (čísla a polohy) – ponk/storemaps.json obsahuje už zkontrolovaná data.
Denní export ho přibalí do dat pro telefon.

  python3 tools/build_store_maps.py            # potřebuje: tesseract, numpy, scipy, pillow
"""
import io
import json
import re
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

CMS = "https://www.bauhaus.cz/api/catalog/vue_storefront_catalog/cms_block/_search"
UA = {"User-Agent": "Ponk/0.5 (open-source)", "Content-Type": "application/json"}
OUT = Path(__file__).resolve().parent.parent / "ponk" / "storemaps.candidates.json"  # návrh k ruční kontrole


def fetch(url, body=None):
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body else None, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def map_urls():
    res = json.loads(fetch(CMS, {"size": 50, "query": {"prefix": {"identifier": "product_finder_"}}}))
    out = {}
    for h in res["hits"]["hits"]:
        s = h["_source"]
        m = re.search(r'<img[^>]+src="([^"]+)"', s.get("content", ""))
        if m:
            out[s["identifier"].rsplit("_", 1)[-1]] = m.group(1)
    return out


def red_mask(a):
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    return (r > 170) & (g < 90) & (b < 90)


def ocr(crop):
    """Přečte číslo / rozsah z výřezu rámečku (červený text → černý na bílém, zvětšeno)."""
    mask = red_mask(crop)
    img = Image.fromarray(np.where(mask, 0, 255).astype(np.uint8)).resize(
        (crop.shape[1] * 4, crop.shape[0] * 4), Image.LANCZOS)
    pad = Image.new("L", (img.width + 40, img.height + 40), 255)
    pad.paste(img, (20, 20))
    with tempfile.NamedTemporaryFile(suffix=".png") as f:
        pad.save(f.name)
        txt = subprocess.run(["tesseract", f.name, "-", "--psm", "7", "-c", "tessedit_char_whitelist=0123456789-"],
                             capture_output=True, text=True).stdout
    return txt.strip().replace(" ", "")


def zone_for(a, box):
    """Barevná plocha, ve které rámeček leží (zaplavení od okolní barvy)."""
    x, y, w, h = box
    H, W = a.shape[:2]
    samples = []
    for px, py in ((x - 4, y + h // 2), (x + w + 3, y + h // 2), (x + w // 2, y - 4), (x + w // 2, y + h + 3)):
        if 0 <= px < W and 0 <= py < H:
            c = a[py, px].astype(int)
            if not (c > 235).all() and not red_mask(a[py:py + 1, px:px + 1])[0, 0]:
                samples.append((px, py, c))
    if not samples:
        return None
    px, py, c = samples[0]
    near = (np.abs(a.astype(int) - c).sum(axis=2) < 40)
    lab, _ = ndimage.label(near)
    comp = lab[py, px]
    if comp == 0:
        return None
    ys, xs = np.where(lab == comp)
    zx, zy, zw, zh = int(xs.min()), int(ys.min()), int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)
    if zw * zh > W * H * 0.35:  # podklad celé mapy, ne zóna
        return None
    return [zx, zy, zw, zh]


def parse(text):
    m = re.fullmatch(r"(\d{1,3})(?:-(\d{1,3}))?", text)
    if not m:
        return None
    lo = int(m.group(1))
    hi = int(m.group(2)) if m.group(2) else lo
    return (lo, hi) if lo <= hi else None


def labels_for(img):
    a = np.asarray(img.convert("RGB"))
    mask = red_mask(a)
    lab, n = ndimage.label(mask)
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab), start=1):
        y0, y1, x0, x1 = sl[0].start, sl[0].stop, sl[1].start, sl[1].stop
        w, h = x1 - x0, y1 - y0
        if not (14 <= w <= 90 and 9 <= h <= 22):
            continue
        comp = lab[sl] == i
        # rámeček = obvod tvořený červenou, vnitřek převážně světlý
        edge = np.concatenate([comp[0], comp[-1], comp[:, 0], comp[:, -1]]).mean()
        inner = a[y0 + 2:y1 - 2, x0 + 2:x1 - 2]
        if edge < 0.7 or inner.size == 0 or (inner.mean(axis=2) > 200).mean() < 0.45:
            continue
        rng = parse(ocr(a[y0:y1, x0:x1]))
        if not rng:
            continue
        out.append({"lo": rng[0], "hi": rng[1], "box": [int(x0), int(y0), int(w), int(h)],
                    "zone": zone_for(a, (x0, y0, w, h))})
    out.sort(key=lambda l: (l["lo"], l["hi"]))
    return out


def main():
    urls = map_urls()
    maps = {}
    for store, url in sorted(urls.items()):
        try:
            img = Image.open(io.BytesIO(fetch(url)))
        except Exception as e:
            print(store, "mapu nejde stáhnout:", e, file=sys.stderr)
            continue
        labels = labels_for(img)
        maps[store] = {"image": url, "width": img.width, "height": img.height, "labels": labels}
        print(f"{store}: {len(labels)} označení regálů", file=sys.stderr)
    OUT.write_text(json.dumps(maps, ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
