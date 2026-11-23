#!/usr/bin/env python3
"""Builds the scene themes' pictures (Forest, Ocean, Hearth) for the app.

The originals in Tools/Themes/Originals are the owner-approved illustrations
(generated 22 November 2026 with Versely's own onboarding art and welcome
mountains as the style reference; prompts in the project files,
themes/v3/PROMPTS.md). Kept untouched; this script writes:

- ThemeSceneForest, ThemeSceneHearth: the picture as it is (JPEG).
- ThemeSceneOcean: the lake with its foreground swells taken out (the water
  under them continues the calm band above, so nothing doubles while they
  move) and the bright crest lines of the far water softened, since they sit
  behind the last lines of text; and ThemeSceneOceanSwell / ThemeSceneOceanNearSwell: the swells as
  transparent layers the reader moves (the far one with a lead-in of the
  water's colour fading in, so it meets the lake above without an edge). Their numbers (where the band starts,
  the padding added around it) are mirrored in `ThemeSceneArt` in Swift.

Run: python3 Tools/Themes/make_scenes.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ORIGINALS = ROOT / "Tools/Themes/Originals"
ASSETS = ROOT / "Genesis/Resources/Assets.xcassets"

# Ocean: the first row of the swells (the rows above are flat, even water),
# where the nearer swells start (feathered), and the padding around the layer.
SWELL_TOP = 2070
NEAR_TOP = 2400
NEAR_FEATHER = 90
FAR_LEAD = 120
# Ocean: the far water's crest lines, softened toward each row's own middle.
FAR_WATER = (1590, 1845)
FAR_SOFTEN = 0.45
SIDE_PAD = 40
BOTTOM_PAD = 80


def imageset(name: str, filename: str, image: Image.Image, **save) -> None:
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.iterdir():
        if old.name != "Contents.json":
            old.unlink()
    image.save(folder / filename, **save)
    (folder / "Contents.json").write_text(
        '{\n  "images" : [\n    {\n      "filename" : "%s",\n      "idiom" : "universal"\n    }\n  ],\n'
        '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n' % filename
    )


def swell_layer(rgb: np.ndarray, top: int, feather: int = 0, lead: int = 0) -> Image.Image:
    band = rgb[top:]
    if lead:
        # A lead-in above the swells: their first row repeated, fading in.
        band = np.concatenate([np.repeat(band[:1], lead, axis=0), band], axis=0)
        feather = lead
    # Padding, so a swell that rises or sways never shows its edge: the
    # bottom row repeated (the foot is an even gradient), the sides mirrored.
    band = np.concatenate([band, np.repeat(band[-1:], BOTTOM_PAD, axis=0)], axis=0)
    band = np.concatenate([band[:, SIDE_PAD:0:-1], band, band[:, -2:-SIDE_PAD - 2:-1]], axis=1)
    alpha = np.full(band.shape[:2], 255, dtype=np.uint8)
    if feather:
        ramp = (np.linspace(0, 1, feather) ** 1.5 * 255).astype(np.uint8)
        alpha[:feather] = ramp[:, None]
    return Image.fromarray(np.dstack([band, alpha]).astype(np.uint8), "RGBA")


def main() -> None:
    for name in ("forest", "hearth"):
        image = Image.open(ORIGINALS / f"{name}.png").convert("RGB")
        imageset(f"ThemeScene{name.capitalize()}", f"scene-{name}.jpg", image, quality=84, optimize=True)

    ocean = np.asarray(Image.open(ORIGINALS / "ocean.png").convert("RGB")).astype(np.float64)
    height = ocean.shape[0]
    # The calm water under the swells: the band above, carried on down to
    # the colour of the original's last row.
    base = ocean.copy()
    top, bottom = FAR_WATER
    band = base[top:bottom]
    middle = np.median(band, axis=1, keepdims=True)
    brighter = band > middle
    band[brighter] = (middle + (band - middle) * FAR_SOFTEN)[brighter]
    above, last = ocean[SWELL_TOP - 1].mean(axis=0), ocean[-1].mean(axis=0)
    for y in range(SWELL_TOP, height):
        t = (y - SWELL_TOP) / max(1, height - 1 - SWELL_TOP)
        base[y] = above * (1 - t) + last * t
    imageset("ThemeSceneOcean", "scene-ocean.jpg", Image.fromarray(base.round().astype(np.uint8)), quality=84, optimize=True)
    imageset("ThemeSceneOceanSwell", "scene-ocean-swell.png", swell_layer(ocean.round().astype(np.uint8), SWELL_TOP, lead=FAR_LEAD), optimize=True)
    imageset(
        "ThemeSceneOceanNearSwell", "scene-ocean-near-swell.png",
        swell_layer(ocean.round().astype(np.uint8), NEAR_TOP, NEAR_FEATHER), optimize=True,
    )
    print("Scene pictures written to", ASSETS)


if __name__ == "__main__":
    main()
