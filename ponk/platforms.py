"""Akumulátorové platformy (Ryobi ONE+, Einhell Power X-Change, Bosch Power for All…).

Bauhaus platformu nemá jako parametr, takže se pozná ze značky, názvu a napětí. U nářadí se
z obsahu balení pozná, jestli je „tělo“ (bez akumulátoru), nebo sada s akumulátorem, a podle
modelu se k tělu najde sada (kolik ušetří, kdo už baterii má).
"""
import re

# id, název, značky (přesně, malými písmeny), podmínka na název (regex), výchozí napětí z názvu
PLATFORMS = [
    ("ryobi_one", "Ryobi ONE+ 18 V", {"ryobi"}, r"one\+|\b18 ?v\b|\b(r|ry|rdd|rpd|rid|rad|rrs|ocs|olt|obl|oht)18", ("36", "max power", "usb")),
    ("ryobi_36", "Ryobi MAX POWER 36 V", {"ryobi"}, r"max power|\b36 ?v\b|\bry36", ()),
    ("einhell_pxc", "Einhell Power X-Change", {"einhell", "einhell professional"}, r"power x-change|pxc|\b(18|36)/\d", ()),
    ("bosch_pfa", "Bosch Power for All 18 V (zelený)", {"bosch", "gardena"}, r"power for all|\b18 ?v\b|\b18 ?li\b|\b18\b", ("12 ?v", "\\b12\\b")),
    ("bosch_pro18", "Bosch Professional 18 V (modrý)", {"bosch professional"}, r"18 ?v|\b18\b|procore18", ()),
    ("bosch_pro12", "Bosch Professional 12 V (modrý)", {"bosch professional"}, r"12 ?v|\b12\b", ()),
    ("makita_lxt", "Makita LXT 18 V", {"makita"}, r"\blxt\b|\b18 ?v\b|\bd[a-z]{2,3}\d{3}", ("xgt", "40 ?v", "cxt", "12 ?v")),
    ("makita_xgt", "Makita XGT 40 V", {"makita"}, r"\bxgt\b|40 ?v", ()),
    ("dewalt_18", "DeWalt XR 18 V", {"dewalt"}, r"\bxr\b|18 ?v|\bdc[a-z]{1,3}\d{3}", ("12 ?v",)),
    ("metabo_18", "Metabo CAS 18 V", {"metabo"}, r"\b18\b|18 ?v|cas", ("powermaxx", "10,8", "12 ?v")),
    ("aeg_18", "AEG 18 V", {"aeg"}, r"18|\bb[a-z]{2,4}18", ()),
    ("worx_ps", "Worx PowerShare 20 V", {"worx"}, r".", ("40 ?v",)),
    ("bd_18", "Black+Decker 18 V", {"black+decker"}, r"18 ?v|\b18\b|[a-z]{3,4}18|\b(bd|bl|bc|gtc|st|gkc|gwc|bcd|bdc|bdcd)[a-z]*\d", ("12 ?v", "36 ?v", "7,2", "3,6")),
    ("hikoki_mv", "HiKOKI 18 V / MultiVolt", {"hikoki"}, r".", ()),
    ("narex_cam", "Narex CAMOUFLAGE 22 V", {"narex"}, r"camouflage|22", ()),
    ("skil_20", "Skil 20 V MAX", {"skil"}, r"20 ?v|\b20\b|\d{4}\s?[a-z]{2}", ("12 ?v",)),
    ("scheppach_20", "Scheppach 20 V IXES", {"scheppach"}, r"ixes|20 ?v|\b20\b", ()),
    ("karcher_18", "Kärcher Battery Power 18 V", {"kärcher"}, r"18|battery", ("36",)),
    ("karcher_36", "Kärcher Battery Power 36 V", {"kärcher"}, r"36", ()),
]

TITLES = {p[0]: p[1] for p in PLATFORMS}
CORDLESS = re.compile(r"\baku\b|akumul|bez aku|solo|one\+|power x-change|power for all|powershare|\blxt\b|\bxgt\b", re.I)
BATTERY_IN_BOX = re.compile(r"akumul|li-?ion|li-power|článek|\d+(,\d+)?\s?ah\b|power ?pack", re.I)
BODY_IN_NAME = re.compile(r"bez akumul|bez bateri|bez aku\b|\bsolo\b|-0\b|\.9\b|\b[a-z]{2,4}\d{2,4}[a-z]?z\b|\bdc[a-z]{1,3}\d{3}n\b", re.I)
KIT_IN_NAME = re.compile(r"\bsada\b|\bkit\b|\bset\b|\d+(,\d+)?\s?ah\b|\d{2}[a-z]?-\d{3}[a-z]?\b", re.I)


def platform_of(brand, name):
    b = (brand or "").lower()
    n = (name or "").lower()
    for pid, _, brands, rx, exclude in PLATFORMS:
        if b in brands and re.search(rx, n) and not any(re.search(x, n) for x in exclude):
            return pid
    return None


def kind_of(name, cat3):
    n = (name or "").lower()
    c = (cat3 or "").lower()
    if "nabíječ" in n and "akumul" in n:
        return "set"  # sada akumulátoru a nabíječky
    if "akumulátory a nabíječky" in c or re.match(r".*\b(akumulátor|nabíječka)\b", n) and "aku " not in n:
        return "battery"
    return "tool"


def model_of(brand, name):
    """Model bez kódu výbavy: Ryobi R18AG-140S → R18AG, Makita DHP453SYE → DHP453."""
    words = (name or "").split()
    idx = next((i for i, w in enumerate(words) if re.search(r"\d", w)), None)
    if idx is None:
        return None
    prev = words[idx - 1] if idx > 0 else ""
    if re.fullmatch(r"[A-Za-z][A-Za-z+\-]*", prev) and re.search(r"[A-Z]", prev) and prev.lower() not in ("aku", "one+", "hp", "lxt", "xgt", "xr"):
        idx -= 1
    model = " ".join(words[idx:]).upper()
    b = (brand or "").lower()
    if b == "makita":
        m = re.match(r"[A-Z]+\d+", model)
        return m.group(0) if m else model
    if b in ("ryobi", "dewalt", "hikoki", "black+decker"):
        model = re.split(r"-|\s", model)[0]
        if b == "dewalt":
            model = re.sub(r"(N|NT|P2|D2|M2|L2|S2)$", "", model)
        return model
    return re.sub(r"\s*\b(SOLO|BEZ AKUMULÁTORU.*|KIT|SET)\b.*$", "", model).strip()


def classify(brand, name, cat3, box):
    """(platforma, druh, tělo bez aku 1/0/None, model) nebo None, když nejde o aku nářadí."""
    pid = platform_of(brand, name)
    if not pid:
        return None
    if not CORDLESS.search(name or "") and kind_of(name, cat3) == "tool" and "akumul" not in (cat3 or "").lower():
        return None
    kind = kind_of(name, cat3)
    body = None
    if kind == "tool":
        if box:
            body = 0 if BATTERY_IN_BOX.search(box) else 1
        elif BODY_IN_NAME.search(name or ""):
            body = 1
        elif KIT_IN_NAME.search(name or ""):
            body = 0
    return pid, kind, body, model_of(brand, name) if kind == "tool" else None
