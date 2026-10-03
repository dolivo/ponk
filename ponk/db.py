import sqlite3
import unicodedata
from .config import DB_PATH, DATA_DIR, DEFAULT_SETTINGS

SCHEMA = """
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS products(
  sku TEXT PRIMARY KEY, pid INTEGER, name TEXT, url_path TEXT, brand TEXT,
  cat1 TEXT, cat2 TEXT, cat3 TEXT, cat_path TEXT,
  image TEXT, gallery TEXT,
  price REAL, was_price REAL, min30_price REAL, real_discount INTEGER,
  labels TEXT, online_qty REAL, online_in_stock INTEGER,
  unit_price REAL, unit TEXT, unit_factor REAL,
  rating INTEGER, rating_count INTEGER, rank INTEGER, ean TEXT, usps TEXT, dims TEXT, positions TEXT,
  created_at TEXT, first_seen TEXT, last_seen TEXT, active INTEGER DEFAULT 1,
  prev_price REAL, price_changed_at TEXT, drop_pct REAL,
  description TEXT, description_at TEXT, search TEXT
);
CREATE INDEX IF NOT EXISTS p_cat ON products(cat1, cat2, cat3);
CREATE INDEX IF NOT EXISTS p_brand ON products(brand);
CREATE INDEX IF NOT EXISTS p_price ON products(price);
CREATE INDEX IF NOT EXISTS p_disc ON products(real_discount);
CREATE INDEX IF NOT EXISTS p_changed ON products(price_changed_at);
CREATE TABLE IF NOT EXISTS price_history(sku TEXT, day TEXT, price REAL, PRIMARY KEY(sku, day)) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS stock(sku TEXT, store TEXT, qty REAL, PRIMARY KEY(sku, store)) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS stock_store ON stock(store, sku);
CREATE TABLE IF NOT EXISTS attrs(code TEXT PRIMARY KEY, label TEXT, input TEXT, filterable INTEGER);
CREATE TABLE IF NOT EXISTS product_attrs(sku TEXT, code TEXT, value TEXT, PRIMARY KEY(sku, code, value)) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS pa_code ON product_attrs(code, value);
CREATE TABLE IF NOT EXISTS stores(code TEXT PRIMARY KEY, name TEXT, city TEXT);
CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE IF NOT EXISTS runs(id INTEGER PRIMARY KEY, started TEXT, finished TEXT, status TEXT,
  products INTEGER, changed INTEGER, new INTEGER, error TEXT);
CREATE TABLE IF NOT EXISTS restock(sku TEXT, store TEXT, day TEXT, PRIMARY KEY(sku, store, day)) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS restock_day ON restock(day, store);
CREATE TABLE IF NOT EXISTS watch(sku TEXT PRIMARY KEY, added TEXT, added_price REAL, target REAL);
CREATE TABLE IF NOT EXISTS saved(id INTEGER PRIMARY KEY, name TEXT, query TEXT, created TEXT, checked TEXT);
"""


def connect():
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(DB_PATH, timeout=30)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA busy_timeout=30000")
    return con


def init():
    con = connect()
    con.executescript(SCHEMA)
    # starší databáze: sloupce přidané v novějších verzích
    cols = {r[1] for r in con.execute("PRAGMA table_info(products)")}
    if "rating_count" not in cols:
        con.execute("ALTER TABLE products ADD COLUMN rating_count INTEGER")
    # běh přerušený vypnutím počítače
    con.execute("UPDATE runs SET status='interrupted' WHERE status='running'")
    for k, v in DEFAULT_SETTINGS.items():
        con.execute("INSERT OR IGNORE INTO settings VALUES(?,?)", (k, v))
    con.commit()
    con.close()


def get_settings(con):
    return {r["key"]: r["value"] for r in con.execute("SELECT key, value FROM settings")}


def fold(text):
    """Malá písmena bez diakritiky – pro vyhledávání 'sroubovak' == 'šroubovák'."""
    text = unicodedata.normalize("NFKD", text or "")
    return "".join(c for c in text if not unicodedata.combining(c)).lower()
