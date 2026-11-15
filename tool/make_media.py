"""Compose the README media from the source art in docs/media/src/.

One-off helper: the raw art is what an image model produced, this adds the
wordmark (in the app's own Inter, Bengali and Devanagari faces) and writes the
sizes the README actually links to. Re-run it after replacing a raw file:

    python3 tool/make_media.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
MEDIA = ROOT / "docs" / "media"
FONTS = ROOT / "assets" / "fonts"

INK = (7, 11, 20)
BRAND = (27, 110, 243)
BRIGHT = (122, 176, 255)
CYAN = (56, 217, 248)
MINT = (67, 224, 160)
AMBER = (255, 181, 69)
TEXT = (244, 248, 255)
MUTED = (166, 186, 220)

W, H = 1600, 880


def font(name: str, size: int, weight: int | None = None) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(FONTS / name), size)
    if weight is not None:
        try:
            f.set_variation_by_axes([size, weight])
        except Exception:
            pass
    return f


def tracked_text(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int],
    text: str,
    f: ImageFont.FreeTypeFont,
    fill,
    tracking: float = 0.0,
) -> int:
    """Draw text with letter-spacing; returns the width consumed."""
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=f, fill=fill)
        x += draw.textlength(ch, font=f) + tracking
    return int(x - xy[0])


def rich_run(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int],
    parts: list[tuple[str, ImageFont.FreeTypeFont, tuple[int, int, int]]],
) -> int:
    """Draw a single line built from several fonts (scripts need their own face)."""
    x, y = xy
    for text, f, fill in parts:
        draw.text((x, y), text, font=f, fill=fill)
        x += draw.textlength(text, font=f)
    return int(x - xy[0])


def pill_shape(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int],
    label_width: float,
    dot: tuple[int, int, int],
) -> tuple[int, int]:
    """Rounded chip on a transparent overlay; returns (width, label_x)."""
    pad_x, gap, h = 26, 14, 56
    w = int(pad_x * 2 + 16 + gap + label_width)
    x, y = xy
    draw.rounded_rectangle(
        (x, y, x + w, y + h), radius=h // 2, fill=(10, 16, 30, 155), outline=(104, 146, 216, 130), width=2
    )
    draw.ellipse((x + pad_x, y + h // 2 - 6, x + pad_x + 12, y + h // 2 + 6), fill=dot + (255,))
    return w, x + pad_x + 16 + gap


def build_hero() -> None:
    art = Image.open(MEDIA / "src" / "hero.jpg").convert("RGB")
    # cover-crop the 1376x768 art to 1600x880 without distorting it
    scale = max(W / art.width, H / art.height)
    art = art.resize((round(art.width * scale), round(art.height * scale)), Image.LANCZOS)
    left = (art.width - W) // 2
    top = (art.height - H) // 2
    hero = art.crop((left, top, left + W, top + H))

    # a left-to-right scrim so the wordmark never fights the art
    scrim = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(scrim)
    for i in range(W // 2):
        a = int(214 * (1 - i / (W // 2)) ** 1.25)
        sd.line([(i, 0), (i, H)], fill=(5, 8, 15, a))
    hero = Image.alpha_composite(hero.convert("RGBA"), scrim)

    # hairline brand bar along the bottom edge
    bar = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bar)
    for x in range(W):
        t = x / W
        col = (
            int(BRAND[0] + (CYAN[0] - BRAND[0]) * t),
            int(BRAND[1] + (CYAN[1] - BRAND[1]) * t),
            int(BRAND[2] + (CYAN[2] - BRAND[2]) * t),
            255,
        )
        bd.line([(x, H - 6), (x, H)], fill=col)
    hero = Image.alpha_composite(hero, bar)

    d = ImageDraw.Draw(hero)
    x = 104

    eyebrow = font("Inter-Variable.ttf", 21, 700)
    tracked_text(d, (x, 150), "FLUTTER  ·  KOTLIN  ·  ANDROID", eyebrow, CYAN, tracking=3.2)

    title = font("Inter-Variable.ttf", 104, 800)
    d.text((x - 6, 196), "ReplyMate AI", font=title, fill=TEXT)

    # amber underline word: the mascot's eyes
    d.rounded_rectangle((x, 330, x + 96, 338), radius=4, fill=AMBER)

    tagline = font("Inter-Variable.ttf", 38, 500)
    bengali = font("NotoSansBengali-Variable.ttf", 40, 600)
    devanagari = font("NotoSansDevanagari-Variable.ttf", 38, 600)
    rich_run(
        d,
        (x, 372),
        [
            ("AI replies in ", tagline, MUTED),
            ("বাংলা", bengali, TEXT),
            ("  ·  ", tagline, (110, 130, 165)),
            ("हिन्दी", devanagari, TEXT),
            ("  ·  ", tagline, (110, 130, 165)),
            ("English", tagline, TEXT),
        ],
    )

    sub = font("Inter-Variable.ttf", 31, 400)
    d.text((x, 452), "You read every draft. Nothing is sent for you.", font=sub, fill=(146, 168, 205))

    # chips go on their own overlay: drawing asemi-transparent fill straight onto an
    # RGBA image punches a hole in the alpha channel instead of blending.
    chip = font("Inter-Variable.ttf", 25, 600)
    chips = [("No auto-send", MINT), ("Works offline", CYAN), ("Your own key", AMBER)]
    chips_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cd = ImageDraw.Draw(chips_layer)
    label_positions = []
    cx, y = 104, 604
    for label, dot in chips:
        w, label_x = pill_shape(cd, (cx, y), d.textlength(label, font=chip), dot)
        label_positions.append((label_x, label))
        cx += w + 18
    hero = Image.alpha_composite(hero, chips_layer)
    d = ImageDraw.Draw(hero)
    cy = 604
    for label_x, label in label_positions:
        d.text((label_x, cy + 13), label, font=chip, fill=(226, 236, 252))

    hero.convert("RGB").save(MEDIA / "hero.jpg", quality=92, optimize=True, progressive=True)


def build_feature(src: str, dst: str, size: int = 640) -> None:
    im = Image.open(MEDIA / src).convert("RGB")
    im = im.resize((size, size), Image.LANCZOS)
    im.save(MEDIA / dst, quality=90, optimize=True, progressive=True)


if __name__ == "__main__":
    build_hero()
    build_feature("src/notification.jpg", "feature-notification.jpg")
    build_feature("src/bubble.jpg", "feature-bubble.jpg")
    build_feature("src/private.jpg", "feature-private.jpg")
    for p in sorted(m for m in MEDIA.rglob("*") if m.is_file()):
        print(f"{str(p.relative_to(MEDIA)):28} {p.stat().st_size / 1024:8.1f} KB")
