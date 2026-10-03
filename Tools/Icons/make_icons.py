#!/usr/bin/env python3
"""Draws Genesis's app icons (the main icon and the alternates people can
choose in Settings › App Icon): an open book on textured paper, with a
seasonal motif for Autumn, Winter, Spring and Summer.

    python3 Tools/Icons/make_icons.py

Writes 1024×1024 PNGs into Genesis/Resources/Assets.xcassets (app icon
sets, plus small previews the app shows in its icon picker). Needs Pillow.
Replace the main icon with a designer's artwork whenever you like: put it in
AppIcon.appiconset with the same file names.
"""
import json
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ASSETS = os.path.join(ROOT, "Genesis", "Resources", "Assets.xcassets")
S = 4  # draw at 4x, then scale down for smooth edges
SIZE = 1024


def rgb(h):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255)


THEMES = {
    # name: (background, page, ink/accent, motif)
    "AppIcon": (0xF6EFE2, 0xFFFBF3, 0xA8844E, None),
    "AppIcon-Night": (0x161B26, 0x232A39, 0xC9A96E, "star"),
    "AppIcon-Autumn": (0xF1E3CC, 0xFBF3E6, 0xA65F34, "leaf"),
    "AppIcon-Winter": (0xE9EEF1, 0xF8FAFB, 0x5D7A8E, "snow"),
    "AppIcon-Spring": (0xF6ECEA, 0xFFF8F6, 0xA86F7E, "blossom"),
    "AppIcon-Summer": (0xF5ECD8, 0xFFF9EC, 0x4E8481, "sun"),
}


def paper(base, dark=False):
    w = SIZE * S
    image = Image.new("RGB", (w, w), rgb(base))
    grain = Image.new("L", (w, w), 0)
    d = ImageDraw.Draw(grain)
    r = random.Random(3)
    for _ in range(26000):
        x, y = r.random() * w, r.random() * w
        rad = (0.6 + r.random() * 1.2) * S
        d.ellipse([x - rad, y - rad, x + rad, y + rad], fill=int(18 + r.random() * 22))
    grain = grain.filter(ImageFilter.GaussianBlur(S * 0.6))
    ink = Image.new("RGB", (w, w), (255, 255, 255) if dark else (90, 70, 40))
    image = Image.composite(ink, image, grain.point(lambda v: v // 3))
    # Soft light from the top.
    glow = Image.new("L", (w, w), 0)
    ImageDraw.Draw(glow).ellipse([-w * 0.2, -w * 0.55, w * 1.2, w * 0.75], fill=60 if not dark else 28)
    glow = glow.filter(ImageFilter.GaussianBlur(w * 0.12))
    image = Image.composite(Image.new("RGB", (w, w), (255, 255, 255)), image, glow)
    return image


def book(draw, page, ink, cx, cy, width):
    """An open book seen from slightly above: two curved pages and a spine."""
    half = width / 2
    height = width * 0.36
    for side in (-1, 1):
        pts = []
        steps = 60
        for i in range(steps + 1):  # top edge, from spine outward, rising then falling
            t = i / steps
            x = cx + side * t * half
            y = cy - height * 0.5 - math.sin(t * math.pi) * width * 0.05 + t * width * 0.02
            pts.append((x, y))
        for i in range(steps, -1, -1):  # bottom edge back to the spine
            t = i / steps
            x = cx + side * t * half
            y = cy + height * 0.5 - math.sin(t * math.pi) * width * 0.025 + t * width * 0.03
            pts.append((x, y))
        draw.polygon(pts, fill=page, outline=ink, width=int(width * 0.018))
        # Lines of text.
        for line in range(5):
            ly = cy - height * 0.28 + line * height * 0.13
            x0 = cx + side * half * 0.16
            x1 = cx + side * half * (0.84 if line < 4 else 0.55)
            lift = -math.sin(0.5 * math.pi) * width * 0.03
            draw.line([(x0, ly + lift * 0.4), (x1, ly + lift * 0.2 + width * 0.012)], fill=ink + (90,), width=int(width * 0.012))
    draw.line([(cx, cy - height * 0.52), (cx, cy + height * 0.5)], fill=ink, width=int(width * 0.02))
    # Ribbon bookmark.
    rx = cx + width * 0.06
    draw.polygon([(rx, cy + height * 0.45), (rx + width * 0.05, cy + height * 0.45),
                  (rx + width * 0.05, cy + height * 0.82), (rx + width * 0.025, cy + height * 0.74),
                  (rx, cy + height * 0.82)], fill=ink)


def leaf(draw, cx, cy, size, color, angle):
    """A pointed leaf with a stem and veins."""
    a = math.radians(angle)

    def at(x, y):
        return (cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a))

    pts = []
    for i in range(120):
        t = i / 119 * 2 * math.pi
        width = math.copysign(abs(math.sin(t)) ** 1.6, math.sin(t))  # pointed at both ends
        pts.append(at(width * size * 0.36, -math.cos(t) * size * 0.5))
    draw.polygon(pts, fill=color)
    vein = (255, 244, 228)
    draw.line([at(0, -size * 0.42), at(0, size * 0.66)], fill=vein, width=int(size * 0.035))
    for k in (-0.22, -0.02, 0.18):
        for side in (-1, 1):
            draw.line([at(0, size * k), at(side * size * 0.2, size * (k - 0.16))], fill=vein, width=int(size * 0.025))


def motif(draw, kind, ink, cx, cy, size):
    if kind == "leaf":
        leaf(draw, cx - size * 0.28, cy + size * 0.05, size * 0.75, rgb(0xC99541), -35)
        leaf(draw, cx + size * 0.22, cy - size * 0.05, size * 0.95, ink, 25)
    elif kind == "snow":
        for arm in range(6):
            a = math.radians(arm * 60)
            x1, y1 = cx + math.cos(a) * size * 0.5, cy + math.sin(a) * size * 0.5
            draw.line([(cx, cy), (x1, y1)], fill=ink, width=int(size * 0.07))
            for k in (0.3, 0.42):
                bx, by = cx + math.cos(a) * size * k, cy + math.sin(a) * size * k
                for side in (-1, 1):
                    b = a + side * math.radians(45)
                    draw.line([(bx, by), (bx + math.cos(b) * size * 0.13, by + math.sin(b) * size * 0.13)], fill=ink, width=int(size * 0.055))
        draw.ellipse([cx - size * 0.07, cy - size * 0.07, cx + size * 0.07, cy + size * 0.07], fill=ink)
    elif kind == "blossom":
        for petal in range(5):
            a = math.radians(petal * 72 - 90)
            px, py = cx + math.cos(a) * size * 0.24, cy + math.sin(a) * size * 0.24
            r = size * 0.22
            draw.ellipse([px - r, py - r, px + r, py + r], fill=rgb(0xE2A9B5))
        r = size * 0.1
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=ink)
    elif kind == "sun":
        for ray in range(12):
            a = math.radians(ray * 30)
            draw.line([(cx + math.cos(a) * size * 0.3, cy + math.sin(a) * size * 0.3),
                       (cx + math.cos(a) * size * 0.5, cy + math.sin(a) * size * 0.5)], fill=rgb(0xE0B866), width=int(size * 0.06))
        r = size * 0.22
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=rgb(0xE9C46A))
    elif kind == "star":
        pts = []
        for i in range(10):
            a = math.radians(i * 36 - 90)
            rr = size * (0.42 if i % 2 == 0 else 0.17)
            pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
        draw.polygon(pts, fill=ink)


def icon(name, background, page, ink, kind, tinted=False):
    dark = name.endswith("Night")
    image = paper(background, dark=dark).convert("RGBA")
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    w = SIZE * S
    if kind:
        motif(d, kind, rgb(ink), w * 0.5, w * 0.3, w * 0.26)
        book(d, rgb(page) + (255,), rgb(ink), w * 0.5, w * 0.62, w * 0.62)
    else:
        book(d, rgb(page) + (255,), rgb(ink), w * 0.5, w * 0.53, w * 0.66)
    # A soft shadow under the book.
    shadow = Image.new("L", image.size, 0)
    ImageDraw.Draw(shadow).ellipse([w * 0.2, w * (0.78 if kind else 0.7), w * 0.8, w * (0.86 if kind else 0.78)], fill=70)
    shadow = shadow.filter(ImageFilter.GaussianBlur(w * 0.025))
    image = Image.composite(Image.new("RGBA", image.size, (60, 45, 25, 255)), image, shadow.point(lambda v: v // 2))
    image = Image.alpha_composite(image, layer)
    image = image.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    if tinted:
        image = image.convert("L").convert("RGB")
    return image


def write_set(name, images):
    folder = os.path.join(ASSETS, f"{name}.appiconset")
    os.makedirs(folder, exist_ok=True)
    entries = []
    for appearance, image in images:
        file = f"{name}{'-' + appearance if appearance else ''}.png"
        image.save(os.path.join(folder, file))
        entry = {"filename": file, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if appearance:
            entry["appearances"] = [{"appearance": "luminosity", "value": appearance}]
        entries.append(entry)
    with open(os.path.join(folder, "Contents.json"), "w") as out:
        json.dump({"images": entries, "info": {"author": "xcode", "version": 1}}, out, indent=2)


def write_preview(name, image):
    folder = os.path.join(ASSETS, f"IconPreview-{name.replace('AppIcon-', '').replace('AppIcon', 'Default')}.imageset")
    os.makedirs(folder, exist_ok=True)
    file = "preview.png"
    image.resize((180, 180), Image.LANCZOS).save(os.path.join(folder, file))
    with open(os.path.join(folder, "Contents.json"), "w") as out:
        json.dump({"images": [{"filename": file, "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}, out, indent=2)


def main():
    for name, (background, page, ink, kind) in THEMES.items():
        light = icon(name, background, page, ink, kind)
        if name == "AppIcon":
            night = THEMES["AppIcon-Night"]
            dark = icon("AppIcon-Night", night[0], night[1], night[2], None)
            tinted = icon(name, background, page, ink, kind, tinted=True)
            write_set(name, [(None, light), ("dark", dark), ("tinted", tinted)])
        else:
            write_set(name, [(None, light)])
        write_preview(name, light)
        print("wrote", name)


if __name__ == "__main__":
    main()
