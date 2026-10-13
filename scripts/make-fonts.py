"""Builds Clockin's three Fraunces cuts from the variable font.

Each cut is a static instance at fixed axes, renamed so iOS registers it
as its own font, with tabular digits and trimmed to the characters the app
shows. Fraunces ships proportional digits only (no `tnum`), so a countdown
would shift sideways every second; here each digit gets a copy at the
widest digit's width, centred, which the cmap then points to. The copies
sit outside every kerning class, so "1:1" and "4:4" come out the same width.

Usage: make-fonts.py <Fraunces[SOFT,WONK,opsz,wght].ttf> <output dir>
"""

import copy
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

# (style name, axes). WONK off: the leaning n/h/m read as a typo at UI sizes.
CUTS = {
    # The countdown and big numbers: chunky, fully soft.
    "Display": {"opsz": 96, "SOFT": 100, "wght": 900, "WONK": 0},
    # Screen titles.
    "Title": {"opsz": 48, "SOFT": 100, "wght": 700, "WONK": 0},
    # Session names and rows, around 20 pt.
    "Text": {"opsz": 20, "SOFT": 50, "wght": 600, "WONK": 0},
}

FAMILY = "Fraunces Clockin"
POSTSCRIPT = "FrauncesClockin"
# Latin, Latin-1, Latin Extended-A, general punctuation, euro and trademark.
UNICODES = "U+0020-007E,U+00A0-017F,U+2010-205E,U+20AC,U+2122"
DIGITS = "0123456789"


def tabular_digits(font: TTFont) -> None:
    glyf, hmtx = font["glyf"], font["hmtx"]
    cmap = font.getBestCmap()
    names = [cmap[ord(d)] for d in DIGITS]
    width = max(hmtx[name][0] for name in names)
    order = font.getGlyphOrder()
    copies = {}
    for name in names:
        new = f"{name}.tf"
        glyph = copy.deepcopy(glyf[name])
        shift = (width - hmtx[name][0]) // 2
        if glyph.isComposite():
            for component in glyph.components:
                component.x += shift
        elif glyph.numberOfContours > 0:
            glyph.coordinates.translate((shift, 0))
        glyph.recalcBounds(glyf)
        # Setting a glyph also adds it to the glyph order glyf shares.
        glyf[new] = glyph
        hmtx[new] = (width, getattr(glyph, "xMin", 0))
        if new not in order:
            order.append(new)
        copies[name] = new
    font.setGlyphOrder(order)
    for table in font["cmap"].tables:
        if table.isUnicode():
            for code, name in list(table.cmap.items()):
                if name in copies:
                    table.cmap[code] = copies[name]


def rename(font: TTFont, style: str) -> None:
    names = font["name"]
    family = f"{FAMILY} {style}"
    postscript = f"{POSTSCRIPT}-{style}"
    for record in list(names.names):
        if record.nameID in (1, 2, 3, 4, 6, 16, 17, 25):
            names.removeNames(nameID=record.nameID)
    names.setName(family, 1, 3, 1, 0x409)
    names.setName("Regular", 2, 3, 1, 0x409)
    names.setName(f"{postscript};clockin", 3, 3, 1, 0x409)
    names.setName(family, 4, 3, 1, 0x409)
    names.setName(postscript, 6, 3, 1, 0x409)


def trim(path: Path) -> None:
    options = subset.Options()
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.notdef_outline = True
    font = TTFont(path)
    subsetter = subset.Subsetter(options)
    unicodes = subset.parse_unicodes(UNICODES)
    # Keep the tabular copies, which only the cmap reaches.
    subsetter.populate(unicodes=unicodes,
                       glyphs=[f"{font.getBestCmap()[ord(d)]}" for d in DIGITS])
    subsetter.subset(font)
    font.save(path)


def main() -> None:
    source, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    for style, axes in CUTS.items():
        font = instantiateVariableFont(TTFont(source), axes, inplace=False)
        tabular_digits(font)
        rename(font, style)
        path = out / f"{POSTSCRIPT}-{style}.ttf"
        font.save(path)
        trim(path)
        print(f"{path.name}: {path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
