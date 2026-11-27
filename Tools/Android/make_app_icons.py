#!/usr/bin/env python3
"""Android launcher icons for Versely's alternate app icons (Night and the
seasons), from the iOS icons in Genesis/Resources/Assets.xcassets.

Each becomes an adaptive icon whose background layer is the picture, scaled
so the launcher's mask (the middle 72 of 108 dp) shows the open-book V whole;
the standard icon's one-colour layer serves themed icons. Rerun after the iOS
icons change:  python3 Tools/Android/make_app_icons.py
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "Genesis/Resources/Assets.xcassets"
RES = ROOT / "android/app/src/main/res"
NAMES = ["Night", "Autumn", "Winter", "Spring", "Summer"]
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
LAYER_DP, PICTURE_DP = 108, 90

for name in NAMES:
    source = Image.open(ASSETS / f"AppIcon-{name}.appiconset/AppIcon-{name}.png").convert("RGB")
    for density, scale in DENSITIES.items():
        layer = round(LAYER_DP * scale)
        picture = round(PICTURE_DP * scale)
        # The edge beyond the picture is never shown; it takes the picture's corner colour.
        canvas = Image.new("RGB", (layer, layer), source.getpixel((4, source.height - 4)))
        canvas.paste(source.resize((picture, picture), Image.LANCZOS), ((layer - picture) // 2,) * 2)
        folder = RES / f"mipmap-{density}"
        folder.mkdir(exist_ok=True)
        canvas.save(folder / f"ic_launcher_{name.lower()}_background.png", optimize=True)
    (RES / "mipmap-anydpi-v26" / f"ic_launcher_{name.lower()}.xml").write_text(
        f'''<?xml version="1.0" encoding="utf-8"?>
<!-- Versely's {name} icon (Tools/Android/make_app_icons.py, from the iOS AppIcon-{name}). -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_{name.lower()}_background" />
    <foreground android:drawable="@android:color/transparent" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
'''
    )
print("done")
