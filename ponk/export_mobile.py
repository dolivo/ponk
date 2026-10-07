"""Export štíhlé databáze pro telefon (SQLite komprimovaná DEFLATE).

  python -m ponk.export_mobile data/ponk.sqlite3 out/

Vytvoří out/ponk-mobile.sqlite.deflate a out/status.json. Telefon si nejdřív
stáhne status.json a databázi jen tehdy, když je novější než ta, kterou má.
Indexy a vyhledávací sloupec si telefon dopočítá sám (menší stahování).
"""
import hashlib
import json
import os
import re
from collections import Counter
import lzma
import sqlite3
import sys
import zlib
from datetime import datetime, timezone

from . import __version__
from .db import fold

SCHEMA_VERSION = 3

TABLES = """
CREATE TABLE products(
  sku TEXT PRIMARY KEY, name TEXT, brand TEXT, cat1 TEXT, cat2 TEXT, cat3 TEXT, image TEXT,
  price REAL, was_price REAL, min30_price REAL, real_discount INTEGER, labels TEXT,
  online_qty REAL, online_in_stock INTEGER, unit_price REAL, unit TEXT, rating INTEGER, rating_count INTEGER, rank INTEGER,
  ean TEXT, dims TEXT, created TEXT, first_seen TEXT, prev_price REAL, price_changed_at TEXT,
  drop_pct REAL, url_path TEXT, active INTEGER, last_price REAL
);
CREATE TABLE restock(sku TEXT, store TEXT, day TEXT, PRIMARY KEY(sku, store, day)) WITHOUT ROWID;
CREATE TABLE store_maps(store TEXT PRIMARY KEY, image TEXT, width INTEGER, height INTEGER);
CREATE TABLE store_map_labels(store TEXT, lo INTEGER, hi INTEGER, x INTEGER, y INTEGER, w INTEGER, h INTEGER,
  zx INTEGER, zy INTEGER, zw INTEGER, zh INTEGER);
CREATE TABLE price_history(sku TEXT, day TEXT, price REAL, PRIMARY KEY(sku, day)) WITHOUT ROWID;
CREATE TABLE stock(sku TEXT, store TEXT, qty REAL, PRIMARY KEY(sku, store)) WITHOUT ROWID;
CREATE TABLE attrs(code TEXT PRIMARY KEY, label TEXT);
CREATE TABLE attr_values(id INTEGER PRIMARY KEY, code TEXT, value TEXT);
CREATE TABLE product_attrs(sku TEXT, vid INTEGER, PRIMARY KEY(sku, vid)) WITHOUT ROWID;
CREATE TABLE stores(code TEXT PRIMARY KEY, name TEXT, city TEXT);
CREATE TABLE info(key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE vocab(word TEXT PRIMARY KEY, display TEXT, freq INTEGER) WITHOUT ROWID;
"""


WORD = re.compile(r"\w+", re.UNICODE)


def build_vocab(con):
    """Slova z názvů, značek, kategorií a parametrů: bez diakritiky → nejčastější zápis + četnost."""
    count, shown = Counter(), {}
    texts = [" ".join(filter(None, r)) for r in con.execute("SELECT name, brand, cat2, cat3 FROM products WHERE price IS NOT NULL")]
    texts += [r[0] for r in con.execute("SELECT DISTINCT value FROM attr_values")]
    for text in texts:
        for w in WORD.findall((text or "").lower()):
            if len(w) < 3 or w.isdigit() or "_" in w:
                continue
            key = fold(w)
            count[key] += 1
            shown.setdefault(key, Counter())[w] += 1
    return [(k, shown[k].most_common(1)[0][0], n) for k, n in count.items()]


def export(src_path, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    tmp = os.path.join(out_dir, "ponk-mobile.sqlite")
    if os.path.exists(tmp):
        os.remove(tmp)
    dst = sqlite3.connect(tmp)
    dst.executescript("PRAGMA page_size=4096; PRAGMA journal_mode=OFF;" + TABLES)
    dst.execute("ATTACH DATABASE ? AS src", (src_path,))
    # aktivní produkty + 30 dní i ty stažené z nabídky (bez ceny), aby hlídané nezmizely
    today = dst.execute("SELECT date('now', 'localtime')").fetchone()[0]
    dst.execute("""INSERT INTO products SELECT sku, name, brand, cat1, cat2, cat3, image,
        CASE WHEN active = 1 THEN price END, was_price, min30_price, real_discount, labels, online_qty,
        CASE WHEN active = 1 THEN online_in_stock ELSE 0 END, unit_price, unit, rating, rating_count, rank, ean, dims,
        substr(created_at, 1, 10), first_seen, prev_price, price_changed_at, drop_pct, url_path, active, price
        FROM src.products WHERE price IS NOT NULL AND (active = 1 OR last_seen >= date(?, '-30 day'))""", (today,))
    # štítek "Novinka" pro produkty, které se objevily za posledních 14 dní (ne při úplně prvním běhu)
    first_day = dst.execute("SELECT MIN(first_seen) FROM products").fetchone()[0]
    dst.execute("""UPDATE products SET labels = CASE WHEN labels IS NULL OR labels = '' THEN ',new,'
        ELSE labels || 'new,' END
        WHERE first_seen > ? AND first_seen >= date(?, '-14 day') AND COALESCE(labels, '') NOT LIKE '%,new,%'""",
                (first_day, today))
    try:
        dst.execute("INSERT INTO restock SELECT r.* FROM src.restock r JOIN products p ON p.sku = r.sku "
                    "WHERE r.day >= date(?, '-14 day')", (today,))
    except sqlite3.OperationalError:
        pass  # starší databáze bez tabulky naskladnění
    maps_path = os.path.join(os.path.dirname(__file__), "storemaps.json")
    if os.path.exists(maps_path):
        for store, m in json.load(open(maps_path, encoding="utf-8")).items():
            dst.execute("INSERT INTO store_maps VALUES(?,?,?,?)", (store, m["image"], m["width"], m["height"]))
            dst.executemany("INSERT INTO store_map_labels VALUES(?,?,?,?,?,?,?,?,?,?,?)", [
                (store, l["lo"], l["hi"], *l["box"], *(l["zone"] or [None] * 4)) for l in m["labels"]])
    dst.execute("INSERT INTO price_history SELECT h.* FROM src.price_history h JOIN products p ON p.sku = h.sku")
    dst.execute("INSERT INTO stock SELECT s.* FROM src.stock s JOIN products p ON p.sku = s.sku WHERE s.qty > 0")
    dst.execute("INSERT INTO attrs SELECT code, label FROM src.attrs WHERE filterable = 1")
    dst.execute("INSERT INTO attr_values(code, value) SELECT DISTINCT pa.code, pa.value FROM src.product_attrs pa "
                "JOIN attrs a ON a.code = pa.code JOIN products p ON p.sku = pa.sku ORDER BY pa.code, pa.value")
    dst.execute("CREATE INDEX tmp_av ON attr_values(code, value)")
    dst.execute("INSERT OR IGNORE INTO product_attrs SELECT pa.sku, av.id FROM src.product_attrs pa "
                "JOIN products p ON p.sku = pa.sku JOIN attr_values av ON av.code = pa.code AND av.value = pa.value")
    dst.execute("DROP INDEX tmp_av")
    # slovník pro opravu překlepů ve vyhledávání (telefon ho jen načte)
    dst.executemany("INSERT INTO vocab VALUES(?,?,?)", build_vocab(dst))
    dst.execute("INSERT INTO stores SELECT * FROM src.stores")
    last = dst.execute("SELECT finished FROM src.runs WHERE status='ok' ORDER BY id DESC LIMIT 1").fetchone()
    generated = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    counts = {t: dst.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
              for t in ("products", "price_history", "stock", "product_attrs", "restock", "store_map_labels", "vocab")}
    sections_path = os.path.join(os.path.dirname(__file__), "home_sections.json")
    sections = open(sections_path, encoding="utf-8").read() if os.path.exists(sections_path) else "[]"
    info = {"schema": str(SCHEMA_VERSION), "generated_at": generated, "last_run": last[0] if last else "",
            "home_sections": json.dumps(json.loads(sections), ensure_ascii=False), "first_day": first_day or "",
            "server_version": __version__,
            "last_change": dst.execute("SELECT MAX(price_changed_at) FROM products").fetchone()[0] or ""}
    dst.executemany("INSERT INTO info VALUES(?,?)", list(info.items()))
    dst.commit()
    dst.execute("DETACH DATABASE src")
    dst.execute("VACUUM")
    dst.close()

    raw = open(tmp, "rb").read()
    os.remove(tmp)
    files = {}
    # xz je asi o 40 % menší; deflate je záloha, kdyby ho iOS neuměl rozbalit
    xz = lzma.compress(raw, format=lzma.FORMAT_XZ, check=lzma.CHECK_CRC32, preset=6)
    comp = zlib.compressobj(9, zlib.DEFLATED, -15)
    df = comp.compress(raw) + comp.flush()
    for name, data in (("ponk-mobile.sqlite.xz", xz), ("ponk-mobile.sqlite.deflate", df)):
        open(os.path.join(out_dir, name), "wb").write(data)
        files[name] = {"size": len(data), "sha256": hashlib.sha256(data).hexdigest()}
    status = {**{k: v for k, v in info.items() if k != "home_sections"}, "schema": SCHEMA_VERSION, "raw_size": len(raw), "files": files, **counts}
    json.dump(status, open(os.path.join(out_dir, "status.json"), "w"), indent=1)
    return status


if __name__ == "__main__":
    print(json.dumps(export(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "out"), indent=1))
