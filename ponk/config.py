import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = Path(os.environ.get("PONK_DATA", ROOT / "data"))
DB_PATH = DATA_DIR / "ponk.sqlite3"
WEB_DIR = ROOT / "web"

HOST = os.environ.get("PONK_HOST", "0.0.0.0")
PORT = int(os.environ.get("PONK_PORT", "8765"))

BASE = "https://www.bauhaus.cz"
CATALOG = BASE + "/api/catalog/vue_storefront_catalog/"
REVIEWS = BASE + "/api/ext/vaimo-reviews/reviews/"
STOCKS = BASE + "/api/ext/vaimo-storelocator/stocks-api/indice/vue_storefront_catalog/stocksBySkus"
USER_AGENT = "Ponk/0.1 (open-source offline price tracker)"

DEFAULT_SETTINGS = {
    "store": "888",          # Brno Ivanovice
    "sync_time": "06:00",    # denní kontrola cen
    "request_delay": "0.3",  # pauza mezi dotazy (s)
    "sync_stock": "1",       # stahovat skladovost po prodejnách
    "sync_ratings": "1",     # stahovat hodnocení zákazníků (recenze BAUHAUS)
}

LABELS = {
    "sell_off": "Výprodej",
    "sale": "Akce",
    "free_shipping": "Doprava zdarma",
    "only_online": "Jen online",
    "warranty": "Prodloužená záruka",
    "qty_discount": "Množstevní sleva",
    "new": "Novinka",
}

UNITS = {
    "Bezny metr": "bm", "Ctverecni metr": "m²", "kubicky metr": "m³",
    "Kilogram": "kg", "Litr": "l", "Metr": "m", "Mililitr": "ml",
    "Karton": "karton", "Role": "role", "ST": "ks", "BTL": "balení",
}
