"""Vyhledávání a filtry nad lokální databází."""
import json
import re
from datetime import date, timedelta

from . import db
from .config import LABELS

SORTS = {
    "relevance": "p.rank DESC, COALESCE(p.real_discount, 0) DESC, p.name",
    "price_asc": "p.price ASC",
    "price_desc": "p.price DESC",
    "discount": "COALESCE(p.real_discount, 0) DESC, COALESCE(p.drop_pct, 0) DESC",
    "drop": "(p.price_changed_at IS NOT NULL AND p.drop_pct > 0) DESC, p.price_changed_at DESC, p.drop_pct DESC",
    "unit": "p.unit_price IS NULL, p.unit_price ASC",
    "rating": "COALESCE(p.rating, 0) DESC",
    "newest": "p.created_at DESC",
}
PAGE = 30


def _one(q, key, default=None):
    v = q.get(key)
    if isinstance(v, list):
        v = v[0] if v else default
    return v if v not in (None, "") else default


def _many(q, key):
    v = q.get(key) or []
    if isinstance(v, str):
        v = [v]
    out = []
    for x in v:
        out.extend(s for s in x.split("|") if s)
    return out


def build_where(q, skip=()):
    """Vrátí (sql, params). `skip` vynechá filtr, pro který právě počítáme fasety."""
    w, a = ["p.active = 1", "p.price IS NOT NULL"], []
    text = db.fold(_one(q, "q", ""))
    for tok in re.findall(r"[\w\-\+\.]+", text)[:8]:
        w.append("p.search LIKE ?")
        a.append(f"%{tok}%")
    for i, key in enumerate(("cat1", "cat2", "cat3")):
        v = _one(q, key)
        if v and "cat" not in skip:
            w.append(f"p.{key} = ?")
            a.append(v)
    brands = _many(q, "brand")
    if brands and "brand" not in skip:
        w.append(f"p.brand IN ({','.join('?' * len(brands))})")
        a += brands
    if (v := _one(q, "pmin")) is not None and "price" not in skip:
        w.append("p.price >= ?"); a.append(float(v))
    if (v := _one(q, "pmax")) is not None and "price" not in skip:
        w.append("p.price <= ?"); a.append(float(v))
    if (v := _one(q, "disc")) is not None:
        w.append("COALESCE(p.real_discount, 0) >= ?"); a.append(int(v))
    if "label" not in skip:
        for lab in _many(q, "label"):
            if lab in LABELS:
                w.append("p.labels LIKE ?"); a.append(f"%,{lab},%")
    if _one(q, "online") == "1":
        w.append("p.online_in_stock = 1")
    store = _one(q, "store")
    if store and "store" not in skip:
        w.append("EXISTS (SELECT 1 FROM stock s WHERE s.sku = p.sku AND s.store = ? AND s.qty > 0)")
        a.append(store)
    if (v := _one(q, "rating")) is not None:
        w.append("p.rating >= ?"); a.append(int(v) * 20)
    if (v := _one(q, "drop_days")) is not None:
        since = (date.today() - timedelta(days=int(v))).isoformat()
        w.append("p.price_changed_at >= ? AND p.drop_pct > 0"); a.append(since)
    if (v := _one(q, "drop_min")) is not None:
        w.append("p.drop_pct >= ?"); a.append(float(v))
    if _one(q, "unit") == "1":
        w.append("p.unit_price IS NOT NULL")
    if (v := _one(q, "since")) is not None:
        # novinky = poprvé viděné nebo zlevněné až PO posledním zobrazení hledání
        w.append("(p.first_seen > ? OR (p.price_changed_at > ? AND p.drop_pct > 0))"); a += [v, v]
    if _one(q, "watch") == "1":
        w.append("p.sku IN (SELECT sku FROM watch)")
    if (v := _one(q, "skus")) is not None:
        skus = v.split(",")
        w.append(f"p.sku IN ({','.join('?' * len(skus))})"); a += skus
    for key in q:
        if key.startswith("a_") and key[2:] not in skip:
            vals = _many(q, key)
            if vals:
                w.append(f"p.sku IN (SELECT sku FROM product_attrs WHERE code = ? AND value IN ({','.join('?' * len(vals))}))")
                a += [key[2:]] + vals
    return " AND ".join(w), a


ITEM_COLS = ("p.sku, p.name, p.brand, p.image, p.price, p.was_price, p.min30_price, p.real_discount, p.labels, "
             "p.online_in_stock, p.unit_price, p.unit, p.rating, p.prev_price, p.price_changed_at, p.drop_pct, "
             "p.cat3, p.dims")


def items_for(con, rows, store):
    out = [dict(r) for r in rows]
    if not out:
        return out
    skus = [r["sku"] for r in out]
    qty = {}
    if store:
        for r in con.execute(f"SELECT sku, qty FROM stock WHERE store=? AND sku IN ({','.join('?' * len(skus))})",
                             [store] + skus):
            qty[r["sku"]] = r["qty"]
    for r in out:
        r["labels"] = [l for l in (r["labels"] or "").strip(",").split(",") if l]
        r["store_qty"] = qty.get(r["sku"], 0)
    return out


def _num_key(v):
    m = re.match(r"\s*(-?\d+(?:[.,]\d+)?)", v or "")
    return (0, float(m.group(1).replace(",", ".")), v) if m else (1, 0, v)


def search(con, q, my_store=None):
    page = max(1, int(_one(q, "page", 1)))
    sort = SORTS.get(_one(q, "sort", "relevance"), SORTS["relevance"])
    store = _one(q, "store") or my_store
    where, args = build_where(q)
    total = con.execute(f"SELECT COUNT(*) FROM products p WHERE {where}", args).fetchone()[0]
    rows = con.execute(f"SELECT {ITEM_COLS} FROM products p WHERE {where} ORDER BY {sort} LIMIT ? OFFSET ?",
                       args + [PAGE, (page - 1) * PAGE]).fetchall()
    res = {"total": total, "page": page, "pages": (total + PAGE - 1) // PAGE, "items": items_for(con, rows, store)}
    if _one(q, "facets", "1") == "1":
        res["facets"] = facets(con, q)
    return res


def facets(con, q):
    f = {}
    # kategorie: další úroveň pod aktuálně vybranou
    level = "cat3" if _one(q, "cat2") else "cat2" if _one(q, "cat1") else "cat1"
    w, a = build_where(q)
    f["categories"] = {"level": level, "values": [
        {"value": r[0], "count": r[1]} for r in con.execute(
            f"SELECT p.{level}, COUNT(*) c FROM products p WHERE {w} AND p.{level} IS NOT NULL "
            f"GROUP BY 1 ORDER BY c DESC LIMIT 60", a)]}
    w, a = build_where(q, skip=("brand",))
    f["brands"] = [{"value": r[0], "count": r[1]} for r in con.execute(
        f"SELECT p.brand, COUNT(*) c FROM products p WHERE {w} AND p.brand IS NOT NULL GROUP BY 1 ORDER BY c DESC LIMIT 300", a)]
    w, a = build_where(q, skip=("price",))
    lo, hi = con.execute(f"SELECT MIN(p.price), MAX(p.price) FROM products p WHERE {w}", a).fetchone()
    f["price"] = {"min": lo, "max": hi}
    w, a = build_where(q, skip=("label",))
    f["labels"] = []
    for key, name in LABELS.items():
        c = con.execute(f"SELECT COUNT(*) FROM products p WHERE {w} AND p.labels LIKE ?", a + [f"%,{key},%"]).fetchone()[0]
        if c:
            f["labels"].append({"value": key, "label": name, "count": c})
    # parametry (jako "Parametry" na Alze) – jen uvnitř kategorie, jinak by to nedávalo smysl
    f["attrs"] = []
    if _one(q, "cat2") or _one(q, "cat3"):
        w, a = build_where(q)
        total = con.execute(f"SELECT COUNT(*) FROM products p WHERE {w}", a).fetchone()[0] or 1
        rows = con.execute(
            f"SELECT pa.code, pa.value, COUNT(*) c FROM product_attrs pa JOIN products p ON p.sku = pa.sku "
            f"WHERE {w} GROUP BY pa.code, pa.value", a).fetchall()
        groups = {}
        for code, value, c in rows:
            groups.setdefault(code, []).append((value, c))
        labels = {r[0]: r[1] for r in con.execute("SELECT code, label FROM attrs WHERE filterable = 1")}
        cands = []
        for code, vals in groups.items():
            if code not in labels or len(vals) < 2:
                continue
            coverage = sum(c for _, c in vals) / total
            selected = bool(_many(q, "a_" + code))
            if coverage >= 0.25 or selected:
                cands.append((selected, coverage, code, vals))
        cands.sort(key=lambda x: (not x[0], -x[1]))
        for selected, coverage, code, vals in cands[:10]:
            vals.sort(key=lambda v: _num_key(v[0]))
            f["attrs"].append({"code": code, "label": labels[code],
                               "values": [{"value": v, "count": c} for v, c in vals[:60]]})
    return f


def categories(con, q):
    """Strom kategorií: vrací podkategorie pro zadanou cestu."""
    c1, c2 = _one(q, "cat1"), _one(q, "cat2")
    if c2:
        sql, a, lvl = "SELECT cat3, COUNT(*), MIN(image) FROM products WHERE active=1 AND cat1=? AND cat2=? AND cat3 IS NOT NULL GROUP BY 1 ORDER BY 1", [c1, c2], "cat3"
    elif c1:
        sql, a, lvl = "SELECT cat2, COUNT(*), MIN(image) FROM products WHERE active=1 AND cat1=? AND cat2 IS NOT NULL GROUP BY 1 ORDER BY 1", [c1], "cat2"
    else:
        sql, a, lvl = "SELECT cat1, COUNT(*), MIN(image) FROM products WHERE active=1 AND cat1 IS NOT NULL GROUP BY 1 ORDER BY 2 DESC", [], "cat1"
    return {"level": lvl, "values": [{"value": r[0], "count": r[1], "image": r[2]} for r in con.execute(sql, a)]}


def suggest(con, text):
    t = db.fold(text).strip()
    if len(t) < 2:
        return {"products": [], "categories": [], "brands": []}
    like = f"%{t}%"
    prods = [dict(r) for r in con.execute(
        "SELECT sku, name, price, image FROM products WHERE active=1 AND search LIKE ? ORDER BY rank DESC LIMIT 6", (like,))]
    cats = []
    for lvl in ("cat3", "cat2"):
        for r in con.execute(f"SELECT cat1, cat2, cat3, COUNT(*) c FROM products WHERE active=1 AND {lvl} IS NOT NULL "
                             f"GROUP BY cat1, cat2{', cat3' if lvl == 'cat3' else ''} LIMIT 5000"):
            name = r[lvl]
            if t in db.fold(name) and len(cats) < 5:
                cats.append({"cat1": r["cat1"], "cat2": r["cat2"], "cat3": r["cat3"] if lvl == "cat3" else None,
                             "name": name, "count": r["c"]})
    brands = [r[0] for r in con.execute(
        "SELECT brand FROM products WHERE active=1 AND brand IS NOT NULL GROUP BY brand", ()) if t in db.fold(r[0])][:4]
    return {"products": prods, "categories": cats, "brands": brands}


def product(con, sku, store=None):
    r = con.execute("SELECT * FROM products WHERE sku=?", (sku,)).fetchone()
    if not r:
        return None
    p = dict(r)
    p.pop("search", None)
    for k in ("gallery", "usps", "cat_path"):
        p[k] = json.loads(p[k]) if p[k] else []
    p["positions"] = json.loads(p["positions"]) if p["positions"] else {}
    p["labels"] = [l for l in (p["labels"] or "").strip(",").split(",") if l]
    p["history"] = [dict(h) for h in con.execute("SELECT day, price FROM price_history WHERE sku=? ORDER BY day", (sku,))]
    p["stock"] = {s["store"]: s["qty"] for s in con.execute("SELECT store, qty FROM stock WHERE sku=?", (sku,))}
    p["params"] = [{"label": a["label"], "value": a["value"]} for a in con.execute(
        "SELECT a.label, GROUP_CONCAT(pa.value, ', ') value FROM product_attrs pa JOIN attrs a ON a.code = pa.code "
        "WHERE pa.sku=? GROUP BY a.code ORDER BY a.label", (sku,))]
    w = con.execute("SELECT * FROM watch WHERE sku=?", (sku,)).fetchone()
    p["watch"] = dict(w) if w else None
    return p


def home(con, store):
    today_rows = con.execute("SELECT MAX(price_changed_at) FROM products").fetchone()[0]
    sections = []
    def add(title, query, sql, args=()):
        rows = con.execute(f"SELECT {ITEM_COLS} FROM products p WHERE p.active=1 AND p.price IS NOT NULL AND {sql} LIMIT 12", args).fetchall()
        if rows:
            sections.append({"title": title, "query": query, "items": items_for(con, rows, store)})
    watched = con.execute("SELECT COUNT(*) FROM watch w JOIN products p ON p.sku=w.sku WHERE p.price < w.added_price").fetchone()[0]
    add("Hlídané, které zlevnily", {"watch": "1"},
        "p.sku IN (SELECT w.sku FROM watch w WHERE p.price < w.added_price) ORDER BY p.drop_pct DESC")
    if today_rows:
        add("Zlevněno při poslední kontrole", {"drop_days": "1", "sort": "drop"},
            "p.price_changed_at = ? AND p.drop_pct > 0 ORDER BY p.drop_pct DESC", (today_rows,))
    if store:
        sname = (con.execute("SELECT name FROM stores WHERE code=?", (store,)).fetchone() or [store])[0]
        add(f"Doprodej skladem: {sname}", {"label": "sell_off", "store": store, "sort": "discount"},
            "p.labels LIKE '%,sell_off,%' AND EXISTS (SELECT 1 FROM stock s WHERE s.sku=p.sku AND s.store=? AND s.qty>0) "
            "ORDER BY COALESCE(p.real_discount,0) DESC", (store,))
    add("Největší skutečné slevy", {"disc": "30", "sort": "discount"},
        "p.real_discount >= 30 ORDER BY p.real_discount DESC")
    return {"sections": sections, "watched_drops": watched}
