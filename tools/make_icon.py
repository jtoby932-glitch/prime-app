#!/usr/bin/env python3
"""Draws PRIME's original app icon (1024 px, opaque) and writes the asset catalog."""
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

S = 1024
SS = 3  # supersample


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def icon(path: Path):
    big = S * SS
    img = Image.new("RGB", (big, big), (5, 5, 6))
    # soft radial lift behind the mark
    glow = Image.new("L", (big, big), 0)
    gd = ImageDraw.Draw(glow)
    for r in range(int(big * 0.62), 0, -6 * SS):
        a = int(70 * (1 - r / (big * 0.62)) ** 2)
        gd.ellipse([big / 2 - r, big * 0.56 - r, big / 2 + r, big * 0.56 + r], fill=a)
    glow = glow.filter(ImageFilter.GaussianBlur(40 * SS))
    lime = Image.new("RGB", (big, big), (200, 255, 60))
    img = Image.composite(lime, img, glow.point(lambda v: int(v * 0.55)))

    # the peak mark, matching PrimeMark in RootView.swift
    w = big * 0.56
    h = big * 0.56
    x0 = (big - w) / 2
    y0 = big * 0.24
    pts = [(x0, y0 + h), (x0 + w * 0.5, y0), (x0 + w, y0 + h), (x0 + w * 0.74, y0 + h), (x0 + w * 0.5, y0 + h * 0.5), (x0 + w * 0.26, y0 + h)]
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    # diagonal lime gradient for the mark
    grad = Image.new("RGB", (big, big))
    top, mid, bottom = (223, 255, 122), (200, 255, 60), (143, 203, 18)
    gp = grad.load()
    for y in range(0, big, SS):
        for x in range(0, big, SS * 8):
            t = min(1, max(0, (x + y) / (2 * big) * 1.4 - 0.15))
            c = lerp(top, mid, t * 2) if t < 0.5 else lerp(mid, bottom, (t - 0.5) * 2)
            for dx in range(SS * 8):
                for dy in range(SS):
                    if x + dx < big and y + dy < big:
                        gp[x + dx, y + dy] = c
    img = Image.composite(grad, img, mask)
    img = img.resize((S, S), Image.LANCZOS)
    img.save(path, "PNG")


def catalog(root: Path):
    assets = root / "Assets.xcassets"
    (assets / "AppIcon.appiconset").mkdir(parents=True, exist_ok=True)
    (assets / "AccentColor.colorset").mkdir(parents=True, exist_ok=True)
    info = {"author": "xcode", "version": 1}
    (assets / "Contents.json").write_text(json.dumps({"info": info}, indent=2))
    (assets / "AppIcon.appiconset" / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": info,
    }, indent=2))
    (assets / "AccentColor.colorset" / "Contents.json").write_text(json.dumps({
        "colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {
            "red": "0.784", "green": "1.000", "blue": "0.235", "alpha": "1.000"}}}],
        "info": info,
    }, indent=2))
    icon(assets / "AppIcon.appiconset" / "AppIcon-1024.png")


if __name__ == "__main__":
    catalog(Path(sys.argv[1]))
