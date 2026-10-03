"""Tenký klient nad veřejným API bauhaus.cz (Vue Storefront + Elasticsearch)."""
import gzip
import json
import time
import urllib.request

from .config import BASE, CATALOG, REVIEWS, STOCKS, USER_AGENT

# Pole, která nepotřebujeme a jen zvětšují přenos (~40 % dat).
EXCLUDE = ["description", "product_links", "classification_store_sort",
           "producersjson", "configurable_children", "tier_prices"]


class Client:
    def __init__(self, delay=0.3, retries=4):
        self.delay = delay
        self.retries = retries
        self._last = 0.0

    def _request(self, url, payload=None):
        wait = self.delay - (time.time() - self._last)
        if wait > 0:
            time.sleep(wait)
        data = json.dumps(payload).encode() if payload is not None else None
        headers = {"User-Agent": USER_AGENT, "Accept-Encoding": "gzip"}
        if data:
            headers["Content-Type"] = "application/json"
        for attempt in range(self.retries):
            try:
                req = urllib.request.Request(url, data=data, headers=headers)
                with urllib.request.urlopen(req, timeout=60) as r:
                    body = r.read()
                    if r.headers.get("Content-Encoding") == "gzip":
                        body = gzip.decompress(body)
                self._last = time.time()
                return body
            except Exception:
                if attempt == self.retries - 1:
                    raise
                time.sleep(2 ** attempt * 2)

    def json(self, url, payload=None):
        return json.loads(self._request(url, payload))

    # --- katalog -------------------------------------------------------
    def iter_products(self, batch=200, limit=None):
        """Projde celý aktivní katalog stránkováním přes search_after."""
        after, seen = None, 0
        while True:
            q = {
                "size": batch,
                "sort": [{"id": "asc"}],
                "track_total_hits": True,
                "_source": {"excludes": EXCLUDE},
                "query": {"bool": {"filter": [{"term": {"status": 1}}, {"term": {"visibility": 4}}]}},
            }
            if after is not None:
                q["search_after"] = after
            res = self.json(CATALOG + "product/_search", q)
            hits = res["hits"]["hits"]
            total = res["hits"]["total"]
            total = total["value"] if isinstance(total, dict) else total
            if not hits:
                return
            for h in hits:
                yield h["_source"], total
                seen += 1
                if limit and seen >= limit:
                    return
            after = hits[-1]["sort"]

    def product(self, sku, fields=None):
        q = {"size": 1, "query": {"term": {"sku": sku}}}
        if fields:
            q["_source"] = {"includes": fields}
        hits = self.json(CATALOG + "product/_search", q)["hits"]["hits"]
        return hits[0]["_source"] if hits else None

    def attributes(self):
        res = self.json(CATALOG + "attribute/_search", {"size": 2000})
        return [h["_source"] for h in res["hits"]["hits"]]

    def ratings(self, skus):
        """Hodnocení zákazníků BAUHAUS (průměr 1–5 a počet recenzí). Nejvýš 50 kódů na dotaz.

        Recenze sdílí všechny země BAUHAUS (bauhaus.info, .at, .cz…), takže počty zahrnují i ty zahraniční.
        Vrací {sku: (průměr nebo None, počet)}.
        """
        res = self.json(REVIEWS + "getRatings/product_ids/" + ",".join(skus))
        out = {}
        for r in res.get("result") or []:
            allr = next((x for x in r.get("ratings") or [] if x.get("collection_source") == "all"), None)
            if allr and allr.get("count"):
                out[str(r.get("product_id"))] = (float(allr.get("average_rating") or 0), int(allr["count"]))
            else:
                out[str(r.get("product_id"))] = (None, 0)
        return out

    def reviews(self, sku, limit=10, cursor=None):
        """Texty recenzí jednoho produktu (i ze zahraničních webů BAUHAUS, s českým překladem)."""
        url = f"{REVIEWS}getReviews/product_id/{sku}/limit/{limit}/cursor/{cursor or 'false'}/ratings/false"
        return self.json(url).get("result") or {}

    def stocks(self, skus):
        res = self.json(STOCKS, {"skus": list(skus)})
        return res.get("result") or []

    def stores(self):
        """Seznam prodejen z SSR stavu stránky (window.__INITIAL_STATE__)."""
        html = self._request(BASE + "/").decode("utf-8", "replace")
        state = _initial_state(html)
        found = {}

        def walk(o):
            if isinstance(o, dict):
                if "warehouse_identifier" in o and "name" in o:
                    found[str(o["warehouse_identifier"])] = (o["name"].replace("  ", " ").strip(), o.get("city"))
                for v in o.values():
                    walk(v)
            elif isinstance(o, list):
                for v in o:
                    walk(v)
        walk(state)
        return found


def _initial_state(html):
    i = html.find("window.__INITIAL_STATE__")
    j = html.find("{", i)
    depth, in_str, esc = 0, False, False
    for k in range(j, len(html)):
        c = html[k]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return json.loads(html[j:k + 1])
    return {}
