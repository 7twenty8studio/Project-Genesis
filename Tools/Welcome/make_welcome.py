#!/usr/bin/env python3
"""Builds the welcome screen's pictures in Assets.xcassets:

- WelcomeMountains: the misty mountains,
after the owner's welcome-screen mockup: a cream sky warming to peach, then
ridges in the brand's sand, copper and walnut, each fading into valley mist,
the nearest with a fringe of trees. Drawn rather than upscaled so it stays
sharp on every screen; wide enough for an iPad held sideways. Seeded, so
  it draws the same picture every time.
- WelcomeIcon, WelcomeWordmark and LaunchLogo (the launch screen): the app
  icon and wordmark, scaled from the logo kit's 2048 px PNGs
  (branding/versely-logo-kit in the project files).

    python3 Tools/Welcome/make_welcome.py <versely-logo-kit folder>

Needs numpy and Pillow.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ASSETS = os.path.join(ROOT, "Genesis/Resources/Assets.xcassets")
# imageset -> (file in the kit, long side in pixels at @3x)
KIT = {
    "WelcomeIcon": ("icon/versely-icon.png", 3 * 132),
    "WelcomeWordmark": ("wordmark/versely-wordmark.png", 3 * 280),
    "LaunchLogo": ("icon/versely-icon.png", 3 * 110),
}
W, H = 2732, 2796
SKY_TOP, SKY_HORIZON = (251, 242, 229), (243, 214, 182)
MIST = np.array((246, 224, 198), float)
# far to near: ridge colour, height of its line (share of H), roughness, trees
RIDGES = [
    ((236, 203, 167), 0.53, 0.040, False),
    ((222, 180, 141), 0.59, 0.050, False),
    ((199, 147, 106), 0.65, 0.060, False),
    ((170, 113, 74), 0.715, 0.065, False),
    ((128, 79, 46), 0.795, 0.070, True),
    ((86, 50, 27), 0.870, 0.060, True),
]
rng = np.random.default_rng(7)


def ridge_line(height, rough, trees):
    x = np.linspace(0, 1, W)
    y = np.zeros(W)
    amp, freq = rough, 1.2
    for _ in range(5):  # rolling hills: summed waves with random phases
        y += amp * np.sin(2 * np.pi * (freq * x + rng.random()))
        amp *= 0.42
        freq *= 1.9
    smooth = (height + y * 0.5) * H
    if trees:  # a fringe of treetops along the nearest ridges
        y += 0.0035 * np.abs(np.sin(np.pi * x * rng.uniform(260, 340) + rng.random() * 6))
        y += 0.0015 * rng.standard_normal(W)
    return (height + y * 0.5) * H, smooth


def save_imageset(name, picture, filename, scale=None, **options):
    folder = os.path.join(ASSETS, name + ".imageset")
    os.makedirs(folder, exist_ok=True)
    picture.save(os.path.join(folder, filename), optimize=True, **options)
    image = {"filename": filename, "idiom": "universal"}
    if scale:
        images = [{"idiom": "universal", "scale": s} for s in ("1x", "2x")] + [dict(image, scale=scale)]
    else:
        images = [image]
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")
    print(name, picture.size, os.path.getsize(os.path.join(folder, filename)) // 1024, "KB")


def mountains():
    yy = np.arange(H)[:, None] / H
    sky = np.array(SKY_TOP, float) + (np.array(SKY_HORIZON, float) - SKY_TOP) * np.clip(yy / 0.62, 0, 1)[..., None]
    image = np.broadcast_to(sky, (H, W, 3)).copy()
    rows = np.arange(H)[:, None]
    for i, (colour, height, rough, trees) in enumerate(RIDGES):
        top, smooth = ridge_line(height, rough, trees)
        depth = rows - top[None, :]
        inside = depth >= 0
        # darkest at the ridge line, fading into mist further down (measured
        # from the smooth line, so treetops don't streak the mist)
        fade = np.clip((rows - smooth[None, :]) / (H * (0.10 + 0.02 * i)), 0, 1)[..., None]
        haze = 0.70 - 0.11 * i
        layer = np.array(colour, float) * (1 - fade * haze) + MIST * fade * haze
        edge = np.clip(depth / 2.0, 0, 1)[..., None]  # anti-aliased ridge
        image = np.where(inside[..., None], image * (1 - edge) + layer * edge, image)
    # the last ridge settles into deep walnut at the very bottom
    bottom = np.clip((yy - 0.90) / 0.10, 0, 1)[..., None]
    image = image * (1 - bottom * 0.55) + np.array((58, 33, 18), float) * bottom * 0.55
    # fine film grain so the gradients never band
    image += rng.normal(0, 1.4, image.shape)
    picture = Image.fromarray(np.clip(image, 0, 255).astype(np.uint8))

    save_imageset("WelcomeMountains", picture, "welcome-mountains.jpg", quality=86, progressive=True)


def kit_pictures(kit):
    for name, (path, side) in KIT.items():
        picture = Image.open(os.path.join(kit, path)).convert("RGBA")
        picture = picture.crop(picture.getbbox())
        picture.thumbnail((side, side), Image.LANCZOS)
        save_imageset(name, picture, name.lower() + ".png", scale="3x")


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    mountains()
    kit_pictures(sys.argv[1])


if __name__ == "__main__":
    main()
