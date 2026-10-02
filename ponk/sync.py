"""Denní stažení katalogu, historie cen a skladovosti."""
import json
import threading
import traceback
from datetime import date, datetime

from . import db
from .bauhaus import Client
from .config import DATA_DIR, LABELS, UNITS

OPTIONS_CACHE = DATA_DIR / "attribute_options.json"

STATUS = {"running": False, "phase": "", "done": 0, "total": 0, "started": None, "message": ""}
_lock = threading.Lock()


def _num(v):
    try:
        v = float(v)
        return v if v > 0 else None
    except (TypeError, ValueError):
        return None


def _opt_maps(attrs):
    maps = {}
    for a in attrs:
        opts = {str(o.get("value")): (o.get("label") or "").strip() for o in a.get("options") or []}
        maps[a["attribute_code"]] = opts
    return maps


def _label(maps, code, value):
    if value in (None, "", 0, "0"):
        return None
    lab = maps.get(code, {}).get(str(value))
    if lab:
        return lab
    return str(value).strip() if isinstance(value, str) else None


def normalize(src, maps):
    """Převede dokument z Elasticsearch na řádek tabulky products + parametry."""
    sku = str(src.get("sku"))
    tree = src.get("category_tree") or []
    price = _num(src.get("final_price_incl_tax")) or _num(src.get("price_incl_tax")) or _num(src.get("regular_price"))
    was = _num(src.get("original_price_incl_tax")) or _num(src.get("regular_price"))
    if was and price and was <= price:
        was = None
    hmp = src.get("history_min_price") or {}
    unit = None
    if src.get("prepocetceny"):
        raw = _label(maps, "jednotkaprepoctu", src.get("jednotkaprepoctu"))
        unit = UNITS.get(raw, raw)
    stock = src.get("stock") or {}
    positions = {}
    for store, rows in (src.get("position_in_store_array") or {}).items():
        if rows:
            r = rows[0]
            positions[store] = {"shelf": r.get("shelf"), "field": r.get("field"),
                                "zone": (r.get("description") or "").strip()}
    gallery = [g.get("image_webp") or g.get("image") for g in src.get("media_gallery") or []
               if g.get("typ", "image") == "image"]
    usps = [src.get(f"usp{i}") for i in range(1, 6) if src.get(f"usp{i}")]
    brand = _label(maps, "manufacturer", src.get("manufacturer"))
    labels = [l for l in src.get("labels") or [] if l in LABELS]
    p = {
        "sku": sku, "pid": src.get("id"), "name": (src.get("name") or "").strip(),
        "url_path": src.get("url_path"), "brand": brand,
        "cat1": tree[0] if len(tree) > 0 else None,
        "cat2": tree[1] if len(tree) > 1 else None,
        "cat3": tree[2] if len(tree) > 2 else None,
        "cat_path": json.dumps(tree, ensure_ascii=False),
        "image": src.get("image_webp") or src.get("image"),
        "gallery": json.dumps(gallery),
        "price": price, "was_price": was,
        "min30_price": _num(hmp.get("min_price")),
        "real_discount": hmp.get("percentage_discount") or None,
        "labels": "," + ",".join(labels) + "," if labels else "",
        "online_qty": _num(stock.get("qty")) or 0,
        "online_in_stock": 1 if stock.get("is_in_stock") else 0,
        "unit_price": _num(src.get("prepoctenacena")) if unit else None,
        "unit": unit, "unit_factor": _num(src.get("faktorprepoctu")) if unit else None,
        "rating": src.get("rating") or None, "rank": src.get("relevance") or 0,
        "ean": src.get("ean"), "usps": json.dumps(usps, ensure_ascii=False),
        "dims": (src.get("produktklammerung") or "").strip() or None,
        "positions": json.dumps(positions, ensure_ascii=False) if positions else None,
        "created_at": src.get("created_at"),
    }
    p["search"] = db.fold(" ".join(filter(None, [p["name"], brand, p["cat2"], p["cat3"], sku, p["ean"]])))
    params = []
    for code, value in src.items():
        if not code.startswith("atributy_"):
            continue
        if isinstance(value, list):
            values = value
        elif isinstance(value, str) and "," in value and all(x.strip().isdigit() for x in value.split(",")):
            values = value.split(",")
        else:
            values = [value]
        for v in values:
            lab = _label(maps, code, v)
            if lab and len(lab) <= 80:
                params.append((sku, code, lab))
    return p, params


COLS = ["sku", "pid", "name", "url_path", "brand", "cat1", "cat2", "cat3", "cat_path", "image", "gallery",
        "price", "was_price", "min30_price", "real_discount", "labels", "online_qty", "online_in_stock",
        "unit_price", "unit", "unit_factor", "rating", "rank", "ean", "usps", "dims", "positions",
        "created_at", "search"]


def upsert(con, p, params, today):
    """Uloží produkt a při změně ceny zapíše bod historie. Vrací 'new' / 'changed' / None."""
    old = con.execute("SELECT price FROM products WHERE sku=?", (p["sku"],)).fetchone()
    result = None
    if old is None:
        con.execute(f"INSERT INTO products({','.join(COLS)}, first_seen, last_seen, active) "
                    f"VALUES({','.join('?' * len(COLS))}, ?, ?, 1)",
                    [p[c] for c in COLS] + [today, today])
        result = "new"
        if p["price"]:
            con.execute("INSERT OR REPLACE INTO price_history VALUES(?,?,?)", (p["sku"], today, p["price"]))
    else:
        sets = ",".join(f"{c}=?" for c in COLS[1:])
        con.execute(f"UPDATE products SET {sets}, last_seen=?, active=1 WHERE sku=?",
                    [p[c] for c in COLS[1:]] + [today, p["sku"]])
        oldp = old["price"]
        if p["price"] and oldp and abs(p["price"] - oldp) >= 0.5:
            con.execute("UPDATE products SET prev_price=?, price_changed_at=?, drop_pct=? WHERE sku=?",
                        (oldp, today, round((oldp - p["price"]) / oldp * 100, 1), p["sku"]))
            con.execute("INSERT OR REPLACE INTO price_history VALUES(?,?,?)", (p["sku"], today, p["price"]))
            result = "changed"
        elif p["price"] and not oldp:
            con.execute("INSERT OR REPLACE INTO price_history VALUES(?,?,?)", (p["sku"], today, p["price"]))
    con.execute("DELETE FROM product_attrs WHERE sku=?", (p["sku"],))
    con.executemany("INSERT OR IGNORE INTO product_attrs VALUES(?,?,?)", params)
    return result


def save_stock(con, rows, skus):
    con.executemany("DELETE FROM stock WHERE sku=?", [(s,) for s in skus])
    data = []
    for r in rows:
        qty = _num(r.get("qty"))
        if qty and str(r.get("status", "1")) == "1":
            data.append((str(r["product_sku"]), str(r["code"]), qty))
    con.executemany("INSERT OR REPLACE INTO stock VALUES(?,?,?)", data)


def run(limit=None, log=print):
    """Kompletní synchronizace. Bezpečné spustit kdykoli; souběžný běh se odmítne."""
    if not _lock.acquire(blocking=False):
        return False
    con = db.connect()
    today = date.today().isoformat()
    run_id = con.execute("INSERT INTO runs(started, status) VALUES(?, 'running')",
                         (datetime.now().isoformat(timespec="seconds"),)).lastrowid
    con.commit()
    STATUS.update(running=True, phase="Prodejny", done=0, total=0,
                  started=datetime.now().isoformat(timespec="seconds"), message="")
    counts = {"products": 0, "changed": 0, "new": 0}
    try:
        settings = db.get_settings(con)
        client = Client(delay=float(settings.get("request_delay", "0.3")))

        try:
            stores = client.stores()
            for code, (name, city) in stores.items():
                con.execute("INSERT OR REPLACE INTO stores VALUES(?,?,?)", (code, name, city))
            con.commit()
        except Exception as e:
            log(f"Prodejny se nepodařilo načíst: {e}")

        STATUS["phase"] = "Parametry"
        attrs = client.attributes()
        maps = _opt_maps(attrs)
        OPTIONS_CACHE.write_text(json.dumps(maps, ensure_ascii=False), encoding="utf-8")
        con.executemany("INSERT OR REPLACE INTO attrs VALUES(?,?,?,?)", [
            (a["attribute_code"], (a.get("frontend_label") or a["attribute_code"]).strip(),
             a.get("frontend_input"), int(a.get("is_filterable") or 0)) for a in attrs])
        con.commit()

        STATUS["phase"] = "Katalog a ceny"
        for src, total in client.iter_products(limit=limit):
            STATUS["total"] = limit or total
            p, params = normalize(src, maps)
            res = upsert(con, p, params, today)
            counts["products"] += 1
            if res:
                counts[res] += 1
            STATUS["done"] = counts["products"]
            if counts["products"] % 200 == 0:
                con.commit()
                log(f"  katalog {counts['products']}/{total}")
        con.commit()

        # Co dnes v katalogu chybělo, je vyprodané nebo stažené z nabídky.
        if not limit and counts["products"] > 1000:
            con.execute("UPDATE products SET active=0 WHERE last_seen < ?", (today,))
            con.commit()

        if settings.get("sync_stock", "1") == "1":
            STATUS.update(phase="Skladovost na prodejnách", done=0)
            skus = [r[0] for r in con.execute("SELECT sku FROM products WHERE active=1 AND last_seen=?", (today,))]
            STATUS["total"] = len(skus)
            for i in range(0, len(skus), 50):
                chunk = skus[i:i + 50]
                save_stock(con, client.stocks(chunk), chunk)
                STATUS["done"] = i + len(chunk)
                if i % 1000 == 0:
                    con.commit()
                    log(f"  sklad {i}/{len(skus)}")
            con.commit()

        con.execute("UPDATE runs SET finished=?, status='ok', products=?, changed=?, new=? WHERE id=?",
                    (datetime.now().isoformat(timespec="seconds"), counts["products"], counts["changed"],
                     counts["new"], run_id))
        con.commit()
        STATUS["message"] = f"Hotovo: {counts['products']} produktů, {counts['changed']} změn cen, {counts['new']} nových."
        log(STATUS["message"])
        return True
    except Exception as e:
        con.rollback()
        con.execute("UPDATE runs SET finished=?, status='error', error=? WHERE id=?",
                    (datetime.now().isoformat(timespec="seconds"), str(e)[:500], run_id))
        con.commit()
        STATUS["message"] = f"Chyba: {e}"
        log(traceback.format_exc())
        return False
    finally:
        STATUS["running"] = False
        con.close()
        _lock.release()


def refresh_one(con, sku):
    """Živá aktualizace jednoho produktu (tlačítko v detailu)."""
    client = Client(delay=0)
    src = client.product(sku)
    if not src:
        return False
    if OPTIONS_CACHE.exists():
        maps = json.loads(OPTIONS_CACHE.read_text(encoding="utf-8"))
    else:
        maps = _opt_maps(client.attributes())
    p, params = normalize(src, maps)
    upsert(con, p, params, date.today().isoformat())
    con.execute("UPDATE products SET description=?, description_at=? WHERE sku=?",
                (src.get("description"), date.today().isoformat(), sku))
    save_stock(con, client.stocks([sku]), [sku])
    con.commit()
    return True


def fetch_description(con, sku):
    src = Client(delay=0).product(sku, ["description"])
    text = (src or {}).get("description") or ""
    con.execute("UPDATE products SET description=?, description_at=? WHERE sku=?",
                (text, date.today().isoformat(), sku))
    con.commit()
    return text
