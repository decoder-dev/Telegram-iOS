#!/usr/bin/env python3
"""Generate a full premium Телеграм paper-plane icon family."""

from __future__ import annotations

import os
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path("/workspace/Telegram/Telegram-iOS")
ART = Path("/opt/cursor/artifacts")
ART.mkdir(parents=True, exist_ok=True)

# Messenger plane in 1024 space (custom geometry).
PLANE = [
    (268, 520),
    (710, 345),
    (655, 680),
    (560, 690),
    (470, 625),
    (590, 455),
    (405, 555),
    (300, 555),
]
PLANE_COMPACT = [
    (290, 530),
    (690, 360),
    (640, 670),
    (555, 678),
    (480, 620),
    (580, 470),
    (420, 555),
    (320, 555),
]


def lerp(a, b, t: float):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def draw_disc(draw: ImageDraw.ImageDraw, size: int, top, bottom, ratio: float):
    r = size * ratio / 2
    cx = cy = size / 2
    y0, y1 = int(cy - r), int(cy + r) + 1
    for y in range(max(0, y0), min(size, y1)):
        t = (y - (cy - r)) / (2 * r)
        t = max(0.0, min(1.0, t))
        c = lerp(top, bottom, t)
        dy = y + 0.5 - cy
        inside = r * r - dy * dy
        if inside <= 0:
            continue
        half = inside ** 0.5
        x0 = int(cx - half)
        x1 = int(cx + half) + 1
        color = c if len(c) == 4 else (*c, 255)
        draw.line([(x0, y), (x1, y)], fill=color)


def draw_plane(draw: ImageDraw.ImageDraw, size: int, fill, compact: bool = False):
    pts = PLANE_COMPACT if compact else PLANE
    s = size / 1024.0
    draw.polygon([(p[0] * s, p[1] * s) for p in pts], fill=fill)


def make_icon(
    size: int,
    *,
    top,
    bottom,
    plane_fill=(255, 255, 255, 255),
    ring=None,
    style: str = "premium",  # premium | filled
    square_bg=None,
    alpha_outside: bool = True,
    soft_glow: bool = False,
):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0) if alpha_outside else (255, 255, 255, 255))
    draw = ImageDraw.Draw(img)
    compact = size < 60

    if style == "filled":
        if square_bg is not None:
            draw.rectangle([0, 0, size - 1, size - 1], fill=(*square_bg, 255))
        else:
            for y in range(size):
                c = lerp(top, bottom, y / max(1, size - 1))
                draw.line([(0, y), (size, y)], fill=(*c, 255))
        # inset premium disc for filled variants
        if ring is not None:
            r_out = size * 0.92 / 2
            cx = cy = size / 2
            draw.ellipse([cx - r_out, cy - r_out, cx + r_out, cy + r_out], fill=(*ring, 255))
            draw_disc(draw, size, top, bottom, ratio=0.78)
        draw_plane(draw, size, plane_fill, compact=compact)
    else:
        # Premium: outer ring + gradient disc + plane
        if ring is not None:
            r_out = size * 0.94 / 2
            cx = cy = size / 2
            draw.ellipse([cx - r_out, cy - r_out, cx + r_out, cy + r_out], fill=(*ring, 255))
            draw_disc(draw, size, top, bottom, ratio=0.80)
        else:
            draw_disc(draw, size, top, bottom, ratio=0.86)
        draw_plane(draw, size, plane_fill, compact=compact)

    if soft_glow and size >= 120:
        # Subtle outer bloom for marketing/preview sizes
        glow = img.filter(ImageFilter.GaussianBlur(radius=max(1, size // 64)))
        base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        base = Image.alpha_composite(base, glow)
        base = Image.alpha_composite(base, img)
        return base
    return img


# All themes are premium-grade. ring colors are champagne / metal accents.
THEMES = {
    # Core blues
    "blue": dict(top=(70, 185, 245), bottom=(20, 120, 220), plane=(255, 255, 255, 255), ring=(200, 230, 255)),
    "blue_classic": dict(top=(55, 175, 240), bottom=(25, 130, 215), plane=(255, 255, 255, 255), ring=(180, 220, 250)),
    "blue_filled": dict(
        top=(45, 160, 235), bottom=(15, 110, 205), plane=(255, 255, 255, 255),
        ring=(170, 210, 255), style="filled", square_bg=(18, 90, 180),
    ),
    # Blacks
    "black": dict(top=(48, 48, 52), bottom=(8, 8, 10), plane=(255, 255, 255, 255), ring=(180, 180, 190)),
    "black_classic": dict(top=(40, 40, 44), bottom=(12, 12, 14), plane=(255, 255, 255, 255), ring=(160, 160, 170)),
    "black_filled": dict(
        top=(36, 36, 40), bottom=(0, 0, 0), plane=(255, 255, 255, 255),
        ring=(140, 140, 150), style="filled", square_bg=(10, 10, 12),
    ),
    "white_filled": dict(
        top=(252, 252, 255), bottom=(230, 236, 245), plane=(30, 140, 230, 255),
        ring=(220, 200, 140), style="filled", square_bg=(245, 247, 252),
    ),
    # Accent pair (former New1 / New2)
    "new1": dict(top=(120, 100, 255), bottom=(40, 90, 255), plane=(255, 255, 255, 255), ring=(210, 200, 255)),
    "new2": dict(top=(40, 220, 210), bottom=(10, 130, 200), plane=(255, 255, 255, 255), ring=(180, 240, 230)),
    # Named Premium collection
    "premium": dict(top=(255, 220, 140), bottom=(200, 140, 40), plane=(255, 255, 255, 255), ring=(255, 235, 180)),
    "premium_turbo": dict(top=(255, 90, 140), bottom=(110, 40, 255), plane=(255, 230, 160, 255), ring=(255, 200, 90)),
    "premium_black": dict(top=(36, 36, 40), bottom=(0, 0, 0), plane=(255, 205, 90, 255), ring=(210, 170, 70)),
    "premium_night": dict(top=(30, 50, 110), bottom=(5, 10, 40), plane=(220, 230, 255, 255), ring=(140, 170, 255)),
    "premium_rose": dict(top=(255, 180, 190), bottom=(190, 80, 120), plane=(255, 255, 255, 255), ring=(255, 210, 200)),
    "premium_emerald": dict(top=(60, 210, 160), bottom=(10, 110, 90), plane=(255, 245, 210, 255), ring=(200, 230, 160)),
    "premium_sunset": dict(top=(255, 170, 80), bottom=(220, 50, 90), plane=(255, 255, 255, 255), ring=(255, 210, 140)),
    "premium_ice": dict(top=(220, 245, 255), bottom=(100, 170, 230), plane=(255, 255, 255, 255), ring=(230, 245, 255)),
    "premium_carbon": dict(top=(55, 55, 60), bottom=(15, 15, 18), plane=(80, 230, 255, 255), ring=(80, 200, 220)),
    "premium_royal": dict(top=(110, 70, 200), bottom=(40, 15, 90), plane=(255, 220, 120, 255), ring=(220, 180, 90)),
    "premium_aurora": dict(top=(80, 255, 200), bottom=(180, 60, 220), plane=(255, 255, 255, 255), ring=(200, 255, 230)),
}


def render(theme_key: str, size: int, alpha_outside: bool = True) -> Image.Image:
    t = THEMES[theme_key]
    return make_icon(
        size,
        top=t["top"],
        bottom=t["bottom"],
        plane_fill=t["plane"],
        ring=t.get("ring"),
        style=t.get("style", "premium"),
        square_bg=t.get("square_bg"),
        alpha_outside=alpha_outside,
    )


def save_rgba(img: Image.Image, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG")


def save_rgb(img: Image.Image, path: Path, bg=(255, 255, 255)):
    path.parent.mkdir(parents=True, exist_ok=True)
    rgb = Image.new("RGB", img.size, bg)
    rgb.paste(img, mask=img.split()[3])
    rgb.save(path, "PNG")


def write_mapping(folder: str, theme: str, mapping: list[tuple[str, int, str]]):
    base = ROOT / f"{folder}.alticon"
    for name, size, mode in mapping:
        img = render(theme, size, alpha_outside=(mode == "rgba"))
        path = base / name
        if mode == "rgb":
            bg = (0, 0, 0) if "black" in theme or "carbon" in theme or "night" in theme or "royal" in theme else (255, 255, 255)
            if "white" in theme or "ice" in theme:
                bg = (245, 247, 252)
            save_rgb(img, path, bg=bg)
        else:
            save_rgba(img, path)


def premium_only_mapping(name: str) -> list[tuple[str, int, str]]:
    return [(f"{name}@2x.png", 120, "rgba"), (f"{name}@3x.png", 180, "rgba")]


def main():
    # Standard home-screen style sets
    sets = {
        "BlueIcon": ("blue", [
            ("BlueIcon@2x.png", 120, "rgb"), ("BlueIcon@3x.png", 180, "rgb"),
            ("BlueIconIpad@2x.png", 152, "rgb"), ("BlueIconIpad.png", 76, "rgb"),
            ("BlueIconLargeIpad@2x.png", 167, "rgb"),
            ("BlueNotificationIcon@2x.png", 40, "rgba"), ("BlueNotificationIcon@3x.png", 60, "rgba"),
            ("BlueNotificationIcon.png", 20, "rgba"),
        ]),
        "BlueClassicIcon": ("blue_classic", [
            ("BlueClassicIcon@2x.png", 120, "rgb"), ("BlueClassicIcon@3x.png", 180, "rgb"),
            ("BlueClassicIconIpad@2x.png", 152, "rgb"), ("BlueClassicIconIpad.png", 76, "rgb"),
            ("BlueClassicIconLargeIpad@2x.png", 167, "rgb"),
            ("BlueClassicNotificationIcon@2x.png", 40, "rgba"),
            ("BlueClassicNotificationIcon@3x.png", 60, "rgba"),
            ("BlueClassicNotificationIcon.png", 20, "rgba"),
        ]),
        "BlueFilledIcon": ("blue_filled", [
            ("BlueFilledIcon@2x.png", 120, "rgb"), ("BlueFilledIcon@3x.png", 180, "rgb"),
            ("BlueFilledIconIpad@2x.png", 152, "rgb"), ("BlueFilledIconIpad.png", 76, "rgb"),
            ("BlueFilledIconLargeIpad@2x.png", 167, "rgb"),
        ]),
        "BlackIcon": ("black", [
            ("BlackIcon@2x.png", 120, "rgb"), ("BlackIcon@3x.png", 180, "rgb"),
            ("BlackIconIpad@2x.png", 152, "rgb"), ("BlackIconIpad.png", 76, "rgb"),
            ("BlackIconLargeIpad@2x.png", 167, "rgb"),
            ("BlackNotificationIcon@2x.png", 40, "rgba"), ("BlackNotificationIcon@3x.png", 60, "rgba"),
            ("BlackNotificationIcon.png", 20, "rgba"),
        ]),
        "BlackClassicIcon": ("black_classic", [
            ("BlackClassicIcon@2x.png", 120, "rgb"), ("BlackClassicIcon@3x.png", 180, "rgb"),
            ("BlackClassicIconIpad@2x.png", 152, "rgb"), ("BlackClassicIconIpad.png", 76, "rgb"),
            ("BlackClassicIconLargeIpad@2x.png", 167, "rgb"),
            ("BlackClassicNotificationIcon@2x.png", 40, "rgba"),
            ("BlackClassicNotificationIcon@3x.png", 60, "rgba"),
            ("BlackClassicNotificationIcon.png", 20, "rgba"),
        ]),
        "BlackFilledIcon": ("black_filled", [
            ("BlackFilledIcon@2x.png", 120, "rgb"), ("BlackFilledIcon@3x.png", 180, "rgb"),
            ("BlackFilledIconIpad@2x.png", 152, "rgba"), ("BlackFilledIconIpad.png", 76, "rgb"),
            ("BlackFilledIconLargeIpad@2x.png", 167, "rgb"),
        ]),
        "WhiteFilledIcon": ("white_filled", [
            ("WhiteFilledIcon@2x.png", 120, "rgb"), ("WhiteFilledIcon@3x.png", 180, "rgb"),
        ]),
    }
    for folder, (theme, mapping) in sets.items():
        write_mapping(folder, theme, mapping)
        print("wrote", folder)

    # New1 / New2
    new1 = [
        ("New1@2x.png", 120), ("New1@3x.png", 180), ("New1-76.png", 76), ("New1-76@2x.png", 152),
        ("New1-83.5@2x.png", 167), ("New1_29x29.png", 29), ("New1_58x58.png", 58),
        ("New1_80x80.png", 80), ("New1_87x87.png", 87),
        ("New1_notification.png", 20), ("New1_notification@2x.png", 40), ("New1_notification@3x.png", 60),
    ]
    for name, sz in new1:
        save_rgba(render("new1", sz), ROOT / "New1.alticon" / name)
    print("wrote New1")

    new2 = [
        ("New2@2x.png", 120), ("New2@3x.png", 180), ("New2-76.png", 76), ("New2-76@2x.png", 152),
        ("New2-83.5@2x.png", 167), ("New2_notification.png", 20), ("New2_notification@3x.png", 60),
        ("New2-Small.png", 29), ("New2-Small@2x.png", 58), ("New2-Small@3x.png", 87),
        ("New2-Small-40.png", 40), ("New2-Small-40@2x.png", 80),
    ]
    for name, sz in new2:
        save_rgba(render("new2", sz), ROOT / "New2.alticon" / name)
    print("wrote New2")

    # Premium collection (existing + new)
    premium_folders = [
        ("Premium", "premium"),
        ("PremiumTurbo", "premium_turbo"),
        ("PremiumBlack", "premium_black"),
        ("PremiumNight", "premium_night"),
        ("PremiumRose", "premium_rose"),
        ("PremiumEmerald", "premium_emerald"),
        ("PremiumSunset", "premium_sunset"),
        ("PremiumIce", "premium_ice"),
        ("PremiumCarbon", "premium_carbon"),
        ("PremiumRoyal", "premium_royal"),
        ("PremiumAurora", "premium_aurora"),
    ]
    for folder, theme in premium_folders:
        write_mapping(folder, theme, premium_only_mapping(folder))
        print("wrote", folder)

    # DefaultAppIcon (premium blue)
    default = ROOT / "DefaultAppIcon.xcassets/AppIconLLC.appiconset"
    for name, sz in {
        "Simple-iTunesArtwork.png": 1024, "BlueIcon@3x.png": 180, "BlueIcon@2x.png": 120,
        "BlueIcon@2x-1.png": 120, "BlueIconIpad@2x.png": 152, "BlueIconLargeIpad@2x.png": 167,
        "BlueNotificationIcon@3x.png": 60, "BlueNotificationIcon@2x.png": 40,
        "BlueNotificationIcon@2x-1.png": 40, "BlueNotificationIcon.png": 20,
        "Simple@87x87.png": 87, "Simple@80x80.png": 80, "Simple@80x80-1.png": 80,
        "Simple@58x58.png": 58, "Simple@58x58-1.png": 58, "Simple@40x40-1.png": 40, "Simple@29x29.png": 29,
    }.items():
        save_rgba(render("blue", sz), default / name)
    print("wrote DefaultAppIcon")

    for set_name, theme in [
        ("BlueIcon.appiconset", "blue"),
        ("BlueFilledIcon.appiconset", "blue_filled"),
        ("BlackIcon.appiconset", "black"),
        ("BlackFilledIcon.appiconset", "black_filled"),
    ]:
        d = ROOT / "AppIcons.xcassets" / set_name
        if not d.exists():
            continue
        for fn in os.listdir(d):
            if not fn.endswith(".png"):
                continue
            m = re.search(r"@(\d+)x(\d+)", fn)
            if m:
                save_rgba(render(theme, int(m.group(1))), d / fn)
        print("wrote", set_name)

    for key, label in [
        ("blue", "default"), ("premium", "premium"), ("premium_turbo", "turbo"),
        ("premium_black", "premium-black"), ("premium_rose", "rose"),
        ("premium_emerald", "emerald"), ("premium_aurora", "aurora"),
        ("premium_night", "night"), ("premium_royal", "royal"),
    ]:
        save_rgba(render(key, 1024), ART / f"telegram-icon-{label}-1024.png")
    print("done")


if __name__ == "__main__":
    main()
