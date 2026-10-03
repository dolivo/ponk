"""Recenze zákazníků z API BAUHAUS (vaimo-reviews) ve zjednodušené podobě pro web.

Recenze sdílí všechny země BAUHAUS; zahraniční mají český překlad (locale cs-CZ),
původní text se ponechá pro zobrazení „přeloženo z …“.
"""

COUNTRIES = {"de": "Německo", "at": "Rakousko", "ch": "Švýcarsko", "cz": "Česko", "sk": "Slovensko",
             "hr": "Chorvatsko", "si": "Slovinsko", "hu": "Maďarsko", "dk": "Dánsko", "se": "Švédsko",
             "fi": "Finsko", "no": "Norsko", "is": "Island", "lu": "Lucembursko", "tr": "Turecko"}


def _pick(parts):
    """(text v češtině, původní text nebo None, když je originál česky)."""
    parts = parts or []
    cs = next((p for p in parts if p.get("locale") == "cs-CZ"), None)
    orig = next((p for p in parts if p.get("original")), None)
    text = (cs or orig or {}).get("content") or ""
    original = orig.get("content") if orig and orig is not cs else None
    return text.strip(), (original or "").strip() or None


def simplify(res):
    ratings = next((r for r in res.get("ratings") or [] if r.get("collection_source") == "all"), {}) or {}
    dist = {d.get("rating"): d.get("count", 0) for d in ratings.get("rating_distribution") or []}
    items = []
    for r in res.get("reviews") or []:
        title, _ = _pick(r.get("title"))
        text, original = _pick(r.get("text"))
        country = (r.get("country_of_origin") or "").lower()
        replies = []
        for rep in (r.get("replies") or []) + (r.get("reply") or []):
            t, _ = _pick(rep.get("text")) if isinstance(rep.get("text"), list) else (rep.get("text") or "", None)
            if t:
                replies.append({"author": rep.get("author") or "BAUHAUS", "text": t})
        items.append({
            "id": r.get("id"), "author": r.get("author") or "Zákazník", "rating": int(r.get("rating") or 0),
            "date": (r.get("submitted_at") or "")[:10], "title": title, "text": text,
            "translated": original is not None, "original": original,
            "country": COUNTRIES.get(country, country.upper()), "source": r.get("source") or "",
            "verified": r.get("purchaser_type") == "verified", "recommended": r.get("recommended") == "yes",
            "photos": [p.get("url") or p.get("normal") for p in r.get("photos") or [] if isinstance(p, dict)],
            "replies": replies,
        })
    pag = res.get("pagination") or {}
    return {"count": ratings.get("count") or 0, "average": ratings.get("average_rating") or 0,
            "distribution": [dist.get(i, 0) for i in (5, 4, 3, 2, 1)],
            "total": pag.get("filtered_total") or len(items),
            "next": ((pag.get("cursor") or {}).get("next") or None), "items": items}
