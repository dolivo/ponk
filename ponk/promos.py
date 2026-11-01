"""Akce výrobců na produktech BAUHAUS (bannery v detailu produktu).

Bauhaus má u produktů „bannery“: dárek k nákupu (např. Ryobi starter set zdarma),
cashback, soutěže, prodloužený servis. Text je volný, proto se z něj tady určí druh akce,
platnost (od/do), jestli platí jen na prodejně a hodnota dárku.
"""
import html
import re
from datetime import date

MEDIA = "https://media.bauhaus.cz/"

MONTHS = {"ledna": 1, "února": 2, "března": 3, "dubna": 4, "května": 5, "června": 6,
          "července": 7, "srpna": 8, "září": 9, "října": 10, "listopadu": 11, "prosince": 12}
_DATE = r"(\d{1,2})\.\s*(?:(\d{1,2})\.|(" + "|".join(MONTHS) + r"))\s*(\d{4})?"

KINDS = {
    "gift": "Dárek k nákupu",
    "deal": "Množstevní akce",
    "cashback": "Cashback",
    "contest": "Soutěž",
    "service": "Servis a záruka",
    "info": "Informace",
}

# druhy, které se počítají jako „akce“ a dostanou štítek do vyhledávání
LABEL_FOR_KIND = {"gift": "gift", "deal": "promo", "cashback": "promo", "contest": "promo"}


def text_of(description):
    """HTML popis banneru → čistý text."""
    t = html.unescape(html.unescape(description or ""))
    t = re.sub(r"<[^>]+>", "", t)
    return re.sub(r"\s+", " ", t).strip()


def _date(m, fallback_year):
    day = int(m.group(1))
    month = int(m.group(2)) if m.group(2) else MONTHS[m.group(3)]
    year = int(m.group(4)) if m.group(4) else fallback_year
    try:
        return date(year, month, day)
    except ValueError:
        return None


def parse_dates(text, today):
    """Vrátí (od, do) jako date nebo None. „do vyprodání zásob“ datum nemá."""
    low = text.lower()
    end_m = re.search(r"\bdo\s+" + _DATE, low)
    start_m = re.search(r"\bod\s+" + _DATE, low)
    end = start = None
    end_year = int(end_m.group(4)) if end_m and end_m.group(4) else None
    if end_m:
        end = _date(end_m, end_year or (int(start_m.group(4)) if start_m and start_m.group(4) else today.year))
    if start_m:
        start = _date(start_m, int(start_m.group(4)) if start_m.group(4) else (end.year if end else today.year))
    return start, end


def kind_of(text):
    low = text.lower()
    if "soutěž" in low or "vyhrát" in low:
        return "contest"
    if "vrácení" in low or "cashback" in low or "odměn" in low:
        return "cashback"
    if re.search(r"\d\s*\+\s*1", low) and "zdarma" in low:
        return "deal"
    if "zdarma" in low or "dostanete navíc" in low:
        return "gift"
    if "servis" in low or "záruk" in low:
        return "service"
    return "info"


def parse(option, today=None):
    """Volba atributu `banners` → slovník s druhem, platností a textem."""
    today = today or date.today()
    text = text_of(option.get("description"))
    start, end = parse_dates(text, today)
    low = text.lower()
    value = re.search(r"v hodnotě\s+(?:až\s+)?([\d\s]+)\s*kč", low)
    gift = None
    if kind_of(text) == "gift":
        g = re.search(r"(?:získáte|dostanete navíc|máte možnost získat)\s+(?:zdarma\s+)?(.+?)(?:\s+v hodnotě|\s+zdarma|\.)", text, re.I)
        gift = re.sub(r"^navíc\s+", "", g.group(1).split(",")[0].strip()) if g else None
    link = re.search(r'href="([^"]+)"', html.unescape(html.unescape(option.get("description") or "")))
    path = (option.get("path") or "").replace("\\", "/")
    return {
        "id": int(option["value"]),
        "label": option.get("label") or "",
        "text": text,
        "link": link.group(1) if link else None,
        "image": MEDIA + path.lstrip("/") if path else None,
        "background": option.get("background") or "#333333",
        "kind": kind_of(text),
        "gift": gift,
        "start": start.isoformat() if start else None,
        "end": end.isoformat() if end else None,
        "store_only": 1 if ("prodejn" in low and ("pouze" in low or "platí" in low)) else 0,
        "value": int(value.group(1).replace(" ", "")) if value else None,
    }


def is_active(banner, today=None):
    today = (today or date.today()).isoformat()
    return not ((banner.get("end") and banner["end"] < today) or (banner.get("start") and banner["start"] > today))
