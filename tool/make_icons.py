"""Generate the H1 "Bolt H" launcher icons for iOS and Android.

    python tool/make_icons.py        (needs Pillow: pip install pillow)

The geometry is in 0..1 tile units and matches HeroLogoPainter in
lib/ui/hero_logo.dart, so the icon and the in-app logo stay identical.
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
NAVY = (15, 28, 43, 255)
WHITE = (255, 255, 255, 255)
GREEN = (46, 212, 122, 255)

# Two white bars and a two-piece green bolt in place of the crossbar.
BARS = [(0.236, 0.196, 0.389, 0.804), (0.611, 0.196, 0.764, 0.804)]
BAR_RADIUS = 0.045
BOLT = [
    [(0.389, 0.418), (0.565, 0.418), (0.525, 0.492), (0.389, 0.492)],
    [(0.475, 0.492), (0.611, 0.492), (0.611, 0.566), (0.435, 0.566)],
]
TILE_RADIUS = 0.22  # only for icons we round ourselves; iOS masks its own
SS = 4  # supersampling for smooth edges


def mark(draw, size, inset=0.0):
    """Draw the H into a square of `size` px, scaled into the middle (1-2*inset)."""
    span = size * (1 - 2 * inset)
    off = size * inset

    def p(x, y):
        return (off + x * span, off + y * span)

    for x0, y0, x1, y1 in BARS:
        draw.rounded_rectangle([p(x0, y0), p(x1, y1)], radius=BAR_RADIUS * span, fill=WHITE)
    for poly in BOLT:
        draw.polygon([p(x, y) for x, y in poly], fill=GREEN)


def render(size, *, background=True, rounded=False, inset=0.0):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if background:
        if rounded:
            d.rounded_rectangle([0, 0, big - 1, big - 1], radius=TILE_RADIUS * big, fill=NAVY)
        else:
            d.rectangle([0, 0, big, big], fill=NAVY)
    mark(d, big, inset)
    return img.resize((size, size), Image.LANCZOS)


def ios():
    folder = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for f in folder.glob("Icon-App-*.png"):
        # Icon-App-83.5x83.5@2x.png -> 83.5 * 2
        pt, scale = f.stem[len("Icon-App-"):].split("x")[0], f.stem.split("@")[1][:-1]
        px = round(float(pt) * int(scale))
        # App Store rejects icons with alpha; iOS applies its own corner mask.
        render(px).convert("RGB").save(f)
        print(f.name, px)


def android():
    res = ROOT / "android/app/src/main/res"
    dpis = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for dpi, k in dpis.items():
        folder = res / f"mipmap-{dpi}"
        # Legacy icon for Android 7 and older: our own rounded tile.
        render(round(48 * k), rounded=True).save(folder / "ic_launcher.png")
        # Adaptive foreground: 108dp canvas, mark kept inside the 66dp safe zone.
        render(round(108 * k), background=False, inset=0.17).save(folder / "ic_launcher_foreground.png")
        print(dpi)


if __name__ == "__main__":
    ios()
    android()
