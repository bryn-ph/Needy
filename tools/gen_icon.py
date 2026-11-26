"""Build Needy's icon from assets/rolling-dices.png.

Source art: "Rolling Dices" by Delapouite, https://game-icons.net/1x1/delapouite/rolling-dices.html,
licensed CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/). This script restyles it
(colour, background, frame) as a WoW-style icon:

    assets/logo.png      512x512, for project pages (CurseForge, Wago, GitHub)
    Needy/Media/icon.tga 64x64, the in-game addon icon (TOC IconTexture)
    Needy/Media/mark.tga 64x64, the wishlist mark: a heart in the same red and gold (drawn, not from the dice)

Usage:
    .venv\\Scripts\\python tools\\gen_icon.py
"""
import pathlib

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "rolling-dices.png"
LOGO = ROOT / "assets" / "logo.png"
TGA = ROOT / "Needy" / "Media" / "icon.tga"
MARK = ROOT / "Needy" / "Media" / "mark.tga"

SIZE = 512
BG_CENTRE = (128, 30, 34)  # deep loot red
BG_EDGE = (30, 6, 8)
GOLD_TOP = (255, 232, 150)
GOLD_BOTTOM = (196, 128, 36)
FRAME = 26  # gold bevel width


def radial(size: int, inner, outer) -> Image.Image:
    """Radial gradient, lighter a little above centre like a lit icon."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    cx, cy = size / 2, size * 0.42
    maxd = (size / 2) * 1.35
    for y in range(size):
        for x in range(size):
            t = min(1.0, (((x - cx) ** 2 + (y - cy) ** 2) ** 0.5) / maxd)
            px[x, y] = tuple(round(inner[i] + (outer[i] - inner[i]) * t) for i in range(3))
    return img


def vertical(size: int, top, bottom) -> Image.Image:
    img = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        draw.line([(0, y), (size, y)], fill=tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return img


def glyph_mask(scale: float) -> Image.Image:
    """The dice's alpha, scaled and centred on a SIZE canvas."""
    src = Image.open(SOURCE).convert("RGBA").getchannel("A")
    inner = round(SIZE * scale)
    src = src.resize((inner, inner), Image.Resampling.LANCZOS)
    mask = Image.new("L", (SIZE, SIZE), 0)
    off = (SIZE - inner) // 2
    mask.paste(src, (off, off + round(SIZE * 0.02)))
    return mask


def build() -> Image.Image:
    icon = radial(SIZE, BG_CENTRE, BG_EDGE).convert("RGBA")

    mask = glyph_mask(0.70)
    # Soft drop shadow, then a dark outline so the gold reads at small sizes.
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow.putalpha(ImageChops.offset(mask, 6, 10).filter(ImageFilter.GaussianBlur(10)).point(lambda v: v * 0.8))
    icon.alpha_composite(shadow)
    outline = Image.new("RGBA", (SIZE, SIZE), (20, 10, 4, 255))
    outline.putalpha(mask.filter(ImageFilter.MaxFilter(9)))
    icon.alpha_composite(outline)
    gold = vertical(SIZE, GOLD_TOP, GOLD_BOTTOM).convert("RGBA")
    gold.putalpha(mask)
    icon.alpha_composite(gold)

    # Bevelled gold frame: light from the top-left, dark hairlines inside and out.
    frame = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(frame)
    for i in range(FRAME):
        t = i / (FRAME - 1)
        light = tuple(round(GOLD_TOP[k] * (1 - t) + GOLD_BOTTOM[k] * t) for k in range(3))
        dark = tuple(round(c * 0.55) for c in light)
        draw.line([(i, i), (SIZE - 1 - i, i)], fill=light + (255,))            # top
        draw.line([(i, i), (i, SIZE - 1 - i)], fill=light + (255,))            # left
        draw.line([(i, SIZE - 1 - i), (SIZE - 1 - i, SIZE - 1 - i)], fill=dark + (255,))  # bottom
        draw.line([(SIZE - 1 - i, i), (SIZE - 1 - i, SIZE - 1 - i)], fill=dark + (255,))  # right
    draw.rectangle([0, 0, SIZE - 1, SIZE - 1], outline=(10, 6, 2, 255), width=4)
    draw.rectangle([FRAME, FRAME, SIZE - 1 - FRAME, SIZE - 1 - FRAME], outline=(10, 6, 2, 255), width=4)
    icon.alpha_composite(frame)
    return icon


def heart_mask(size: int, scale: float) -> Image.Image:
    """A filled heart (the classic parametric curve), centred on a size x size canvas."""
    import math

    pts = []
    for i in range(720):
        t = 2 * math.pi * i / 720
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((x, y))
    # The curve spans x -16..16 and y -17..12; fit it, flipped so the point is at the bottom.
    k = size * scale / 34
    cx, cy = size / 2, size / 2 - 2.5 * k
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).polygon([(cx + x * k, cy - y * k) for x, y in pts], fill=255)
    return mask


def build_mark() -> Image.Image:
    """The wishlist mark: a crimson heart with a gold rim, in the logo's colours, on transparency."""
    big = 512
    outer = heart_mask(big, 0.98)
    rim = heart_mask(big, 0.86)
    inner = heart_mask(big, 0.70)
    mark = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    dark = Image.new("RGBA", (big, big), (20, 6, 4, 255))
    dark.putalpha(outer)
    mark.alpha_composite(dark)
    gold = vertical(big, GOLD_TOP, GOLD_BOTTOM).convert("RGBA")
    gold.putalpha(rim)
    mark.alpha_composite(gold)
    red = vertical(big, (226, 58, 58), (112, 14, 22)).convert("RGBA")
    red.putalpha(inner)
    mark.alpha_composite(red)
    # A soft glint, top left, so it reads as glossy rather than flat.
    glint = Image.new("L", (big, big), 0)
    ImageDraw.Draw(glint).ellipse([big * 0.27, big * 0.24, big * 0.43, big * 0.36], fill=150)
    glint = ImageChops.multiply(glint.filter(ImageFilter.GaussianBlur(big * 0.02)), inner)
    shine = Image.new("RGBA", (big, big), (255, 235, 220, 255))
    shine.putalpha(glint)
    mark.alpha_composite(shine)
    return mark.resize((64, 64), Image.Resampling.LANCZOS)


def main() -> None:
    build_mark().save(MARK, format="TGA", rle=False)
    print(f"wrote {MARK.relative_to(ROOT)}")
    icon = build()
    LOGO.parent.mkdir(parents=True, exist_ok=True)
    icon.save(LOGO)
    # In game the icon is shown small, so the frame is left out (the UI draws its own).
    small = icon.crop((FRAME, FRAME, SIZE - FRAME, SIZE - FRAME)).resize((64, 64), Image.Resampling.LANCZOS)
    small.save(TGA, format="TGA", rle=False)
    print(f"wrote {LOGO.relative_to(ROOT)} and {TGA.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
