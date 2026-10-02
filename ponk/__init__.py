"""Ponk – neoficiální offline klient pro katalog bauhaus.cz."""
from pathlib import Path

try:
    __version__ = (Path(__file__).resolve().parent.parent / "VERSION").read_text().strip()
except OSError:
    __version__ = "0.0.0"
