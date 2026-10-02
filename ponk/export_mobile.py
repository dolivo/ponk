"""Export štíhlé databáze pro telefon (SQLite komprimovaná DEFLATE).

  python -m ponk.export_mobile data/ponk.sqlite3 out/

Vytvoří out/ponk-mobile.sqlite.deflate a out/status.json. Telefon si nejdřív
stáhne status.json a databázi jen tehdy, když je novější než ta, kterou má.
Indexy a vyhledávací sloupec si telefon dopočítá sám (menší stahování).
"""
import hashlib
import json
import os
import lzma
import sqlite3
import sys
import zlib
from datetime import datetime, timezone

from . import __version__

SCHEMA_VERSION = 3

TABLES = """
CREATE TABLE products(
  sku TEXT PRIMARY KEY, name TEXT, brand TEXT, cat1 TEXT, cat2 TEXT, cat3 TEXT, image TEXT,
  price REAL, was_price REAL, min30_price REAL, real_discount INTEGER, labels TEXT,
  online_qty REAL, online_in_stock INTEGER, unit_price REAL, unit TEXT, rating INTEGER, rank INTEGER,
  ean TEXT, dims TEXT, created TEXT, first_seen TEXT, prev_price REAL, price_changed_at TEXT,
  drop_pct REAL, url_path TEXT
);
CREATE TABLE price_history(sku TEXT, day TEXT, price REAL, PRIMARY KEY(sku, day)) WITHOUT ROWID;
CREATE TABLE stock(sku TEXT, store TEXT, qty REAL, PRIMARY KEY(sku, store)) WITHOUT ROWID;
CREATE TABLE attrs(code TEXT PRIMARY KEY, label TEXT);
CREATE TABLE attr_values(id INTEGER PRIMARY KEY, code TEXT, value TEXT);
CREATE TABLE product_attrs(sku TEXT, vid INTEGER, PRIMARY KEY(sku, vid)) WITHOUT ROWID;
CREATE TABLE stores(code TEXT PRIMARY KEY, name TEXT, city TEXT);
CREATE TABLE info(key TEXT PRIMARY KEY, value TEXT);
"""


def export(src_path, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    tmp = os.path.join(out_dir, "ponk-mobile.sqlite")
    if os.path.exists(tmp):
        os.remove(tmp)
    dst = sqlite3.connect(tmp)
    dst.executescript("PRAGMA page_size=4096; PRAGMA journal_mode=OFF;" + TABLES)
    dst.execute("ATTACH DATABASE ? AS src", (src_path,))
    dst.execute("""INSERT INTO products SELECT sku, name, brand, cat1, cat2, cat3, image, price, was_price,
        min30_price, real_discount, labels, online_qty, online_in_stock, unit_price, unit, rating, rank, ean, dims,
        substr(created_at, 1, 10), first_seen, prev_price, price_changed_at, drop_pct, url_path
        FROM src.products WHERE active = 1 AND price IS NOT NULL""")
    dst.execute("INSERT INTO price_history SELECT h.* FROM src.price_history h JOIN products p ON p.sku = h.sku")
    dst.execute("INSERT INTO stock SELECT s.* FROM src.stock s JOIN products p ON p.sku = s.sku WHERE s.qty > 0")
    dst.execute("INSERT INTO attrs SELECT code, label FROM src.attrs WHERE filterable = 1")
    dst.execute("INSERT INTO attr_values(code, value) SELECT DISTINCT pa.code, pa.value FROM src.product_attrs pa "
                "JOIN attrs a ON a.code = pa.code JOIN products p ON p.sku = pa.sku ORDER BY pa.code, pa.value")
    dst.execute("CREATE INDEX tmp_av ON attr_values(code, value)")
    dst.execute("INSERT OR IGNORE INTO product_attrs SELECT pa.sku, av.id FROM src.product_attrs pa "
                "JOIN products p ON p.sku = pa.sku JOIN attr_values av ON av.code = pa.code AND av.value = pa.value")
    dst.execute("DROP INDEX tmp_av")
    dst.execute("INSERT INTO stores SELECT * FROM src.stores")
    last = dst.execute("SELECT finished FROM src.runs WHERE status='ok' ORDER BY id DESC LIMIT 1").fetchone()
    generated = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    counts = {t: dst.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
              for t in ("products", "price_history", "stock", "product_attrs")}
    info = {"schema": str(SCHEMA_VERSION), "generated_at": generated, "last_run": last[0] if last else "",
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
    status = {**info, "schema": SCHEMA_VERSION, "raw_size": len(raw), "files": files, **counts}
    json.dump(status, open(os.path.join(out_dir, "status.json"), "w"), indent=1)
    return status


if __name__ == "__main__":
    print(json.dumps(export(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "out"), indent=1))
