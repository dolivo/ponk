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


TAG = ("M243 96h158a32 32 0 0 1 32 32v158a32 32 0 0 1-9.4 22.6L282.6 449.4a32 32 0 0 1-45.2 0"
       "L62.6 274.6a32 32 0 0 1 0-45.2L220.4 105.4A32 32 0 0 1 243 96Z")
HOLE = "M386 176a34 34 0 1 0-68 0a34 34 0 1 0 68 0Z"
PLATE = (64, 330, 384, 104)


def icon_svg(variant: str = "light") -> str:
    """Ikona: cenovka nahoře, logo Bauhaus dole.

    light  – světlý podklad (výchozí ikona)
    dark   – průhledný podklad, iOS doplní tmavé pozadí (tmavý režim ikon)
    tinted – jen bílé tvary na průhledném podkladu; iOS je obarví zvolenou barvou.
             Otvor v cenovce a písmena jsou vyříznuté, aby byly vidět i při tónování.
    """
    x, y, w, h = PLATE
    word = word_path("BAUHAUS", x + 26, y + 24, w - 52, h - 48, tracking=0.03)
    plate_path = f"M{x} {y}h{w}v{h}h-{w}Z"
    if variant == "tinted":
        return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <g transform="translate(118 26) scale(0.58)"><path fill="#FFFFFF" fill-rule="evenodd" d="{TAG} {HOLE}"/></g>
  <path fill="#FFFFFF" fill-rule="evenodd" d="{plate_path} {word}"/>
</svg>
"""
    bg = {"light": '<rect width="512" height="512" fill="url(#bgl)"/>', "dark": ""}[variant]
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <defs>
    <linearGradient id="bgl" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#E9EAEC"/>
    </linearGradient>
    <linearGradient id="red" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#E01010"/>
      <stop offset="1" stop-color="#B80000"/>
    </linearGradient>
  </defs>
  {bg}
  <g transform="translate(118 26) scale(0.58)"><path fill="url(#red)" fill-rule="evenodd" d="{TAG} {HOLE}"/></g>
  <rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{RED}"/>
  <path fill="#FFFFFF" d="{word}"/>
</svg>
"""



def png(svg: str, size: int) -> Image.Image:
    return Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg.encode(), output_width=size, output_height=size)))


def main() -> None:
    light = icon_svg("light")
    (ROOT / "web/icon.svg").write_text(light)
    # web/bauhaus-logo.svg a ios/.../BauhausLogo.imageset jsou originální logo (vektor z bauhaus.cz),
    # tento skript je negeneruje.
    icons = ROOT / "ios/Ponk/Resources/Assets.xcassets/AppIcon.appiconset"
    # iOS: výchozí ikona bez průhlednosti, tmavá a tónovaná s průhledným podkladem
    png(light, 1024).convert("RGB").save(icons / "icon-1024.png", optimize=True)
    png(icon_svg("dark"), 1024).convert("RGBA").save(icons / "icon-1024-dark.png", optimize=True)
    png(icon_svg("tinted"), 1024).convert("LA").save(icons / "icon-1024-tinted.png", optimize=True)
    (icons / "Contents.json").write_text("""{ "images" : [
  { "filename" : "icon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
  { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
    "filename" : "icon-1024-dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
  { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ],
    "filename" : "icon-1024-tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ],
  "info" : { "author" : "xcode", "version" : 1 } }
""")
    for path, size in {ROOT / "web/icon-512.png": 512, ROOT / "web/icon-192.png": 192, ROOT / "web/icon-180.png": 180}.items():
        png(light, size).convert("RGB").save(path, optimize=True)
    print("✓ ikony: světlá, tmavá, tónovaná")


if __name__ == "__main__":
    main()
