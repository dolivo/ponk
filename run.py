#!/usr/bin/env python3
"""Ponk – spuštění.

  python run.py            spustí server (web + denní kontrola cen)
  python run.py sync       jednorázově stáhne katalog, ceny a skladovost
  python run.py sync 500   zkušební běh jen pro prvních 500 produktů
"""
import sys

from ponk import db, sync

if __name__ == "__main__":
    db.init()
    if len(sys.argv) > 1 and sys.argv[1] == "sync":
        limit = int(sys.argv[2]) if len(sys.argv) > 2 else None
        ok = sync.run(limit=limit)
        sys.exit(0 if ok else 1)
    from ponk import server
    server.main()
