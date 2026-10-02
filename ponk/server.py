"""Lokální HTTP server: REST API + statický web + plánovač denní kontroly."""
import gzip
import json
import mimetypes
import os
import socket
import threading
import time
import urllib.parse
from datetime import date, datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import db, search, sync
from .config import HOST, PORT, WEB_DIR, LABELS

mimetypes.add_type("application/manifest+json", ".webmanifest")
mimetypes.add_type("font/woff2", ".woff2")


def last_ok_run(con):
    r = con.execute("SELECT * FROM runs WHERE status='ok' ORDER BY id DESC LIMIT 1").fetchone()
    return dict(r) if r else None


def scheduler():
    """Spustí kontrolu v nastavený čas. Když byl počítač vypnutý, dožene ji po startu."""
    time.sleep(15)
    while True:
        try:
            con = db.connect()
            s = db.get_settings(con)
            last = last_ok_run(con)
            con.close()
            now = datetime.now()
            hh, mm = (int(x) for x in s.get("sync_time", "06:00").split(":"))
            due_today = now.replace(hour=hh, minute=mm, second=0, microsecond=0)
            last_start = datetime.fromisoformat(last["started"]) if last else None
            missed = last_start is None or last_start < due_today - timedelta(days=1)
            due = now >= due_today and (last_start is None or last_start < due_today)
            if (due or missed) and not sync.STATUS["running"]:
                threading.Thread(target=sync.run, daemon=True).start()
        except Exception as e:
            print("Plánovač:", e)
        time.sleep(60)


class Handler(BaseHTTPRequestHandler):
    server_version = "Ponk"

    def log_message(self, fmt, *args):
        pass

    # --- odpovědi ------------------------------------------------------
    def send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False, default=str).encode()
        self._send(body, "application/json; charset=utf-8", status)

    def _send(self, body, ctype, status=200, cache=None):
        gz = "gzip" in (self.headers.get("Accept-Encoding") or "") and len(body) > 1200 and not ctype.startswith(("image", "font"))
        if gz:
            body = gzip.compress(body, 5)
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        if gz:
            self.send_header("Content-Encoding", "gzip")
        self.send_header("Cache-Control", cache or "no-store")
        self.end_headers()
        self.wfile.write(body)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}") if n else {}

    # --- směrování -----------------------------------------------------
    def do_GET(self):
        self.route("GET")

    def do_POST(self):
        self.route("POST")

    def do_DELETE(self):
        self.route("DELETE")

    def route(self, method):
        url = urllib.parse.urlsplit(self.path)
        q = urllib.parse.parse_qs(url.query)
        path = url.path
        if not path.startswith("/api/"):
            return self.static(path) if method == "GET" else self.send_json({"error": "not found"}, 404)
        con = db.connect()
        try:
            out = self.api(con, method, path[5:].strip("/").split("/"), q)
            if out is None:
                self.send_json({"error": "Nenalezeno"}, 404)
            else:
                self.send_json(out)
        except Exception as e:
            self.send_json({"error": str(e)}, 500)
        finally:
            con.close()

    def api(self, con, method, parts, q):
        s = db.get_settings(con)
        head = parts[0]
        if head == "meta":
            last = last_ok_run(con)
            n = con.execute("SELECT COUNT(*) FROM products WHERE active=1").fetchone()[0]
            stores = [dict(r) for r in con.execute("SELECT code, name, city FROM stores ORDER BY name")]
            last_change = con.execute("SELECT MAX(price_changed_at) FROM products").fetchone()[0]
            watched = con.execute("SELECT COUNT(*) FROM watch w JOIN products p ON p.sku=w.sku "
                                  "WHERE p.price < w.added_price OR (w.target AND p.price <= w.target)").fetchone()[0]
            return {"settings": s, "stores": stores, "last_run": last, "products": n, "last_change": last_change,
                    "watched_drops": watched, "labels": LABELS, "sync": sync.STATUS}
        if head == "home":
            return search.home(con, s.get("store"))
        if head == "search":
            return search.search(con, q, s.get("store"))
        if head == "suggest":
            return search.suggest(con, (q.get("q") or [""])[0])
        if head == "categories":
            return search.categories(con, q)
        if head == "product" and len(parts) > 1:
            sku = parts[1]
            if (q.get("refresh") or [""])[0] == "1":
                sync.refresh_one(con, sku)
            p = search.product(con, sku, s.get("store"))
            if p and p.get("description") is None and (q.get("desc") or ["1"])[0] == "1":
                try:
                    p["description"] = sync.fetch_description(con, sku)
                except Exception:
                    p["description"] = None  # offline – popis se načte příště
            return p
        if head == "watch":
            if method == "POST":
                b = self.body()
                price = con.execute("SELECT price FROM products WHERE sku=?", (b["sku"],)).fetchone()
                con.execute("INSERT OR REPLACE INTO watch VALUES(?,?,?,?)",
                            (b["sku"], date.today().isoformat(), price[0] if price else None, b.get("target")))
                con.commit()
                return {"ok": True}
            if method == "DELETE" and len(parts) > 1:
                con.execute("DELETE FROM watch WHERE sku=?", (parts[1],))
                con.commit()
                return {"ok": True}
            rows = con.execute(f"SELECT {search.ITEM_COLS}, w.added, w.added_price, w.target FROM watch w "
                               f"JOIN products p ON p.sku = w.sku ORDER BY (p.price < w.added_price) DESC, w.added DESC").fetchall()
            return {"items": search.items_for(con, rows, s.get("store"))}
        if head == "saved":
            if method == "POST":
                b = self.body()
                now = datetime.now().isoformat(timespec="seconds")
                con.execute("INSERT INTO saved(name, query, created, checked) VALUES(?,?,?,?)",
                            (b["name"], json.dumps(b["query"], ensure_ascii=False), now, date.today().isoformat()))
                con.commit()
                return {"ok": True}
            if method == "DELETE" and len(parts) > 1:
                if len(parts) > 2 and parts[2] == "seen":
                    con.execute("UPDATE saved SET checked=? WHERE id=?", (date.today().isoformat(), parts[1]))
                else:
                    con.execute("DELETE FROM saved WHERE id=?", (parts[1],))
                con.commit()
                return {"ok": True}
            out = []
            for r in con.execute("SELECT * FROM saved ORDER BY id DESC").fetchall():
                query = json.loads(r["query"])
                where, args = search.build_where({**query, "since": r["checked"]})
                fresh = con.execute(f"SELECT COUNT(*) FROM products p WHERE {where}", args).fetchone()[0]
                where, args = search.build_where(query)
                total = con.execute(f"SELECT COUNT(*) FROM products p WHERE {where}", args).fetchone()[0]
                out.append({**dict(r), "query": query, "fresh": fresh, "total": total})
            return {"items": out}
        if head == "settings" and method == "POST":
            for k, v in self.body().items():
                if k in ("store", "sync_time", "request_delay", "sync_stock"):
                    con.execute("INSERT OR REPLACE INTO settings VALUES(?,?)", (k, str(v)))
            con.commit()
            return {"ok": True, "settings": db.get_settings(con)}
        if head == "sync":
            if method == "POST" and not sync.STATUS["running"]:
                threading.Thread(target=sync.run, daemon=True).start()
                time.sleep(0.2)
            return sync.STATUS
        return None

    def static(self, path):
        if path in ("", "/"):
            path = "/index.html"
        f = (WEB_DIR / path.lstrip("/")).resolve()
        if not str(f).startswith(str(WEB_DIR)) or not f.is_file():
            f = WEB_DIR / "index.html"  # SPA fallback
        ctype = mimetypes.guess_type(str(f))[0] or "application/octet-stream"
        cache = "public, max-age=604800" if f.suffix == ".woff2" else "no-cache"
        self._send(f.read_bytes(), ctype + ("; charset=utf-8" if ctype.startswith("text") or "javascript" in ctype else ""), cache=cache)


def lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("10.255.255.255", 1))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def main():
    db.init()
    if os.environ.get("PONK_NO_SCHEDULER") != "1":
        threading.Thread(target=scheduler, daemon=True).start()
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Ponk běží:\n  v tomto počítači  http://localhost:{PORT}\n  v mobilu (Wi-Fi)  http://{lan_ip()}:{PORT}")
    print("Ukončení: Ctrl+C")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
