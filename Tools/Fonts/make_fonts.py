#!/usr/bin/env python3
"""Builds the reader's Literata, EB Garamond, Crimson Pro and Source Serif 4
fonts (SIL Open Font License) from Google Fonts' variable fonts: static
Regular, SemiBold and Italic with clean PostScript names, written to
Genesis/Resources/Fonts.

    git clone --depth 1 --filter=blob:none --sparse https://github.com/google/fonts /tmp/gfonts
    (cd /tmp/gfonts && git sparse-checkout set ofl/literata ofl/ebgaramond ofl/crimsonpro ofl/sourceserif4)
    python3 Tools/Fonts/make_fonts.py /tmp/gfonts/ofl

Families whose source isn't checked out are skipped. Needs fontTools. None
of these families declares a Reserved Font Name, so the instances keep their
names. Copy each OFL.txt alongside (Literata-OFL.txt, EBGaramond-OFL.txt,
CrimsonPro-OFL.txt, SourceSerif4-OFL.txt).

Spectral (Premium) is not built here: Google Fonts ships it as static files,
copied unmodified (Spectral-Regular, -SemiBold, -Italic, plus
ofl/spectral/OFL.txt as Spectral-OFL.txt).
"""
import sys
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

OUT = Path(__file__).resolve().parents[2] / "Genesis" / "Resources" / "Fonts"

# source, axis location, PostScript name, (family, subfamily, typographic family, typographic subfamily)
JOBS = [
    ("literata/Literata[opsz,wght].ttf", {"opsz": 12, "wght": 400}, "Literata-Regular", ("Literata", "Regular", "Literata", "Regular")),
    ("literata/Literata[opsz,wght].ttf", {"opsz": 12, "wght": 600}, "Literata-SemiBold", ("Literata SemiBold", "Regular", "Literata", "SemiBold")),
    ("literata/Literata-Italic[opsz,wght].ttf", {"opsz": 12, "wght": 400}, "Literata-Italic", ("Literata", "Italic", "Literata", "Italic")),
    ("ebgaramond/EBGaramond[wght].ttf", {"wght": 400}, "EBGaramond-Regular", ("EB Garamond", "Regular", "EB Garamond", "Regular")),
    ("ebgaramond/EBGaramond[wght].ttf", {"wght": 600}, "EBGaramond-SemiBold", ("EB Garamond SemiBold", "Regular", "EB Garamond", "SemiBold")),
    ("ebgaramond/EBGaramond-Italic[wght].ttf", {"wght": 400}, "EBGaramond-Italic", ("EB Garamond", "Italic", "EB Garamond", "Italic")),
    ("crimsonpro/CrimsonPro[wght].ttf", {"wght": 400}, "CrimsonPro-Regular", ("Crimson Pro", "Regular", "Crimson Pro", "Regular")),
    ("crimsonpro/CrimsonPro[wght].ttf", {"wght": 600}, "CrimsonPro-SemiBold", ("Crimson Pro SemiBold", "Regular", "Crimson Pro", "SemiBold")),
    ("crimsonpro/CrimsonPro-Italic[wght].ttf", {"wght": 400}, "CrimsonPro-Italic", ("Crimson Pro", "Italic", "Crimson Pro", "Italic")),
    ("sourceserif4/SourceSerif4[opsz,wght].ttf", {"opsz": 20, "wght": 400}, "SourceSerif4-Regular", ("Source Serif 4", "Regular", "Source Serif 4", "Regular")),
    ("sourceserif4/SourceSerif4[opsz,wght].ttf", {"opsz": 20, "wght": 600}, "SourceSerif4-SemiBold", ("Source Serif 4 SemiBold", "Regular", "Source Serif 4", "SemiBold")),
    ("sourceserif4/SourceSerif4-Italic[opsz,wght].ttf", {"opsz": 20, "wght": 400}, "SourceSerif4-Italic", ("Source Serif 4", "Italic", "Source Serif 4", "Italic")),
]


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    source = Path(sys.argv[1])
    for path, location, ps, (family, sub, tfamily, tsub) in JOBS:
        if not (source / path).exists():
            print(f"skipped {ps} (no {path})")
            continue
        font = instancer.instantiateVariableFont(TTFont(source / path), location, updateFontNames=True)
        names = font["name"]
        for record in list(names.names):
            if record.nameID in (1, 2, 3, 4, 6, 16, 17, 25):
                names.removeNames(nameID=record.nameID)
        full = f"{tfamily} {tsub}"
        for platform, encoding, language in [(3, 1, 0x409), (1, 0, 0)]:
            for name_id, value in [(1, family), (2, sub), (3, f"{ps};Genesis"), (4, full), (6, ps), (16, tfamily), (17, tsub)]:
                names.setName(value, name_id, platform, encoding, language)
        if "Italic" in ps:
            font["OS/2"].fsSelection = (font["OS/2"].fsSelection | 1) & ~(1 << 6)
            font["head"].macStyle |= 2
        font.save(OUT / f"{ps}.ttf")
        print(ps)


if __name__ == "__main__":
    main()
