#!/usr/bin/env python3
"""Builds the scene themes' pictures (Forest, Ocean, Hearth) for the app.

The originals in Tools/Themes/Originals are the owner-approved illustrations
(generated 22 November 2026 with Versely's own onboarding art and welcome
mountains as the style reference; prompts in the project files,
themes/v3/PROMPTS.md). Kept untouched; this script writes:

- ThemeSceneForest, ThemeSceneHearth: the picture as it is (JPEG).
- ThemeSceneForestCanopy / ThemeSceneForestTrunks / ThemeSceneForestFront:
  the Forest's canopy (its top `CANOPY_ROWS`) in three layers, so the boughs
  sway while the trunks stay planted: the canopy with the trunks painted
  out (it sways), the trunks alone (still, drawn over it) and the dark
  boughs that cross in front of a trunk (they sway, drawn over the trunks).
  `ForestSway` in Swift draws them.
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
# Forest: the canopy's rows (ForestSway.canopy × the height) and its seven
# trunks: each edge a straight line from its column at the top to its column
# at the canopy's foot (None = the picture's own edge), with each trunk's flat
# colour. Each row snaps to the drawn edge when there's one within 4 px.
CANOPY_ROWS = 1266
TRUNKS = [  # ((left top, left foot), (right top, right foot), colour)
    (None, (66, 70), (31, 52, 43)),
    ((117, 84), (153, 149), (191, 189, 167)),
    ((200, 190), (283, 291), (86, 105, 77)),
    ((302, 295), (357, 364), (190, 188, 165)),
    ((1182, 1176), (1250, 1264), (191, 189, 168)),
    ((1287, 1300), (1385, 1414), (87, 106, 78)),
    ((1478, 1457), None, (31, 53, 42)),
]
TRUNK_TOLERANCE = 30
FRONT_MARGIN = 40
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


def trunk_spans(rgb: np.ndarray, left, right, colour) -> list[tuple[int, int]]:
    """Each canopy row's span of one trunk: its straight edges, snapped to
    the drawn edge where one is close (a bough hiding it leaves the line)."""
    width = rgb.shape[1]
    like = np.abs(rgb[:CANOPY_ROWS] - np.array(colour)).sum(axis=2) < TRUNK_TOLERANCE
    spans = []
    for y in range(CANOPY_ROWS):
        t = y / (CANOPY_ROWS - 1)
        row = like[y]
        if left is None:
            l = 0
        else:
            l = round(left[0] + (left[1] - left[0]) * t)
            hits = [x for x in range(max(1, l - 4), min(width, l + 5)) if row[x] and not row[x - 1]]
            if len(hits) == 1:
                l = hits[0]
        if right is None:
            r = width - 1
        else:
            r = round(right[0] + (right[1] - right[0]) * t)
            hits = [x for x in range(max(0, r - 4), min(width - 1, r + 5)) if row[x] and not row[x + 1]]
            if len(hits) == 1:
                r = hits[0]
        spans.append((l, r))
    return spans


def forest_layers(image: Image.Image) -> None:
    rgb = np.asarray(image).astype(np.float64)
    canopy = rgb[:CANOPY_ROWS].copy()
    width = rgb.shape[1]
    trunks = np.zeros((CANOPY_ROWS, width, 4))
    front = np.zeros((CANOPY_ROWS, width, 4))
    luminance = rgb[:CANOPY_ROWS] @ np.array([0.2126, 0.7152, 0.0722])
    for left, right, colour in TRUNKS:
        colour_array = np.array(colour, dtype=np.float64)
        trunk_luminance = colour_array @ np.array([0.2126, 0.7152, 0.0722])
        like = np.abs(rgb[:CANOPY_ROWS] - colour_array).sum(axis=2) < TRUNK_TOLERANCE
        for y, (l, r) in enumerate(trunk_spans(rgb, left, right, colour)):
            # The trunk, solid: its own pixels, its colour where a bough crosses.
            row = np.where(like[y, l:r + 1, None], rgb[y, l:r + 1], colour_array)
            trunks[y, l:r + 1, :3] = row
            trunks[y, l:r + 1, 3] = 255
            for edge in (l - 1, r + 1):
                if 0 <= edge < width and trunks[y, edge, 3] == 0:
                    trunks[y, edge, :3] = colour_array
                    trunks[y, edge, 3] = 128
            # The canopy without it: the colours either side, carried across.
            a, b = max(0, l - 2), min(width - 1, r + 2)
            start = rgb[y, a] if left is not None else rgb[y, b]
            end = rgb[y, b] if right is not None else rgb[y, a]
            ramp = np.linspace(0, 1, r - l + 1)[:, None]
            canopy[y, l:r + 1] = start * (1 - ramp) + end * ramp
            # Boughs in front: darker than the trunk, on it or beside it.
            fa, fb = max(0, l - FRONT_MARGIN), min(width, r + 1 + FRONT_MARGIN)
            darker = (luminance[y, fa:fb] < trunk_luminance - 25) & ~like[y, fa:fb]
            front[y, fa:fb][darker] = np.concatenate([rgb[y, fa:fb][darker], np.full((int(darker.sum()), 1), 255.0)], axis=1)
    imageset("ThemeSceneForestCanopy", "scene-forest-canopy.jpg", Image.fromarray(canopy.round().astype(np.uint8)), quality=84, optimize=True)
    imageset("ThemeSceneForestTrunks", "scene-forest-trunks.png", Image.fromarray(trunks.round().astype(np.uint8), "RGBA"), optimize=True)
    imageset("ThemeSceneForestFront", "scene-forest-front.png", Image.fromarray(front.round().astype(np.uint8), "RGBA"), optimize=True)


def main() -> None:
    for name in ("forest", "hearth"):
        image = Image.open(ORIGINALS / f"{name}.png").convert("RGB")
        imageset(f"ThemeScene{name.capitalize()}", f"scene-{name}.jpg", image, quality=84, optimize=True)
        if name == "forest":
            forest_layers(image)

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
