"""Vygeneruje ikony aplikace (iOS + web) s logem Bauhaus.

Nápis BAUHAUS se převádí na křivky z písma Barlow Semi Condensed ExtraBold,
takže SVG nepotřebuje žádné písmo a PNG jsou ostré v každé velikosti.

    pip install fonttools cairosvg pillow
    python3 tools/make_icons.py
"""
import io
from pathlib import Path

import cairosvg
from PIL import Image
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "ios/Ponk/Resources/Fonts/BarlowSemiCondensed-ExtraBold.ttf"

RED = "#CC0000"
INK = "#262626"


def word_path(text: str, box_x: float, box_y: float, box_w: float, box_h: float, tracking: float = 0.02) -> str:
    """Křivky textu vystředěné do obdélníku (šířka i výška se vejdou)."""
    font = TTFont(FONT)
    gs = font.getGlyphSet()
    cmap = font.getBestCmap()
    upm = font["head"].unitsPerEm
    names = [cmap[ord(c)] for c in text]

    # rozměry v jednotkách písma
    x = 0.0
    placed = []
    bounds = BoundsPen(gs)
    for i, n in enumerate(names):
        placed.append((n, x))
        tp = TransformPen(bounds, (1, 0, 0, 1, x, 0))
        gs[n].draw(tp)
        x += gs[n].width + (tracking * upm if i < len(names) - 1 else 0)
    x0, y0, x1, y1 = bounds.bounds
    w, h = x1 - x0, y1 - y0
    scale = min(box_w / w, box_h / h)
    ox = box_x + (box_w - w * scale) / 2 - x0 * scale
    oy = box_y + (box_h - h * scale) / 2 + y1 * scale  # osa y v písmu míří nahoru

    pen = SVGPathPen(gs, ntos=lambda v: f"{v:.1f}")
    for n, gx in placed:
        gs[n].draw(TransformPen(pen, (scale, 0, 0, -scale, ox + gx * scale, oy)))
    return pen.getCommands()


def icon_svg() -> str:
    # Cenovka (stejný tvar jako dřív) zmenšená do horní části, dole logo Bauhaus.
    tag = ("M243 96h158a32 32 0 0 1 32 32v158a32 32 0 0 1-9.4 22.6L282.6 449.4a32 32 0 0 1-45.2 0"
           "L62.6 274.6a32 32 0 0 1 0-45.2L220.4 105.4A32 32 0 0 1 243 96Z")
    plate = (64, 330, 384, 104)
    word = word_path("BAUHAUS", plate[0] + 26, plate[1] + 24, plate[2] - 52, plate[3] - 48, tracking=0.03)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#303030"/>
      <stop offset="1" stop-color="#1B1B1B"/>
    </linearGradient>
    <linearGradient id="red" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#E01010"/>
      <stop offset="1" stop-color="#B80000"/>
    </linearGradient>
  </defs>
  <rect width="512" height="512" fill="url(#bg)"/>
  <g transform="translate(118 26) scale(0.58)">
    <path fill="url(#red)" d="{tag}"/>
    <circle cx="352" cy="176" r="34" fill="#2A2A2A"/>
  </g>
  <rect x="{plate[0]}" y="{plate[1]}" width="{plate[2]}" height="{plate[3]}" fill="{RED}"/>
  <path fill="#FFFFFF" d="{word}"/>
</svg>
"""


def logo_svg() -> str:
    """Samotné logo (červený obdélník s bílým nápisem) pro web."""
    w, h = 200, 54
    word = word_path("BAUHAUS", 14, 12, w - 28, h - 24, tracking=0.03)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}">
  <rect width="{w}" height="{h}" fill="{RED}"/>
  <path fill="#FFFFFF" d="{word}"/>
</svg>
"""


def main() -> None:
    svg = icon_svg()
    (ROOT / "web/icon.svg").write_text(svg)
    (ROOT / "web/bauhaus-logo.svg").write_text(logo_svg())
    outputs = {
        ROOT / "ios/Ponk/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png": 1024,
        ROOT / "web/icon-512.png": 512,
        ROOT / "web/icon-192.png": 192,
        ROOT / "web/icon-180.png": 180,
    }
    for path, size in outputs.items():
        png = cairosvg.svg2png(bytestring=svg.encode(), output_width=size, output_height=size)
        # iOS chce ikonu bez průhlednosti
        Image.open(io.BytesIO(png)).convert("RGB").save(path, optimize=True)
        print("✓", path.relative_to(ROOT), size)


if __name__ == "__main__":
    main()
