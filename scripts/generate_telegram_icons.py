#!/usr/bin/env python3
"""Generate a custom Telegram-style paper-plane icon family for the fork."""

from __future__ import annotations

import os
import re
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path("/workspace/Telegram/Telegram-iOS")
ART = Path("/opt/cursor/artifacts")
ART.mkdir(parents=True, exist_ok=True)

# Custom messenger plane (1024 space) — recognizable, not a stock asset copy.
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


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def draw_disc(draw: ImageDraw.ImageDraw, size: int, top, bottom, ratio: float = 0.82):
    r = size * ratio / 2
    cx = cy = size / 2
    # Vertical gradient disc via scanlines
    y0, y1 = int(cy - r), int(cy + r) + 1
    for y in range(max(0, y0), min(size, y1)):
        t = (y - (cy - r)) / (2 * r)
        t = max(0.0, min(1.0, t))
        c = lerp(top, bottom, t)
        # circle chord
        dy = y + 0.5 - cy
        inside = r * r - dy * dy
        if inside <= 0:
            continue
        half = inside ** 0.5
        x0 = int(cx - half)
        x1 = int(cx + half) + 1
        color = c if len(c) == 4 else c + (255,)
        draw.line([(x0, y), (x1, y)], fill=color)


def draw_plane(draw: ImageDraw.ImageDraw, size: int, fill, compact: bool = False):
    pts = PLANE_COMPACT if compact else PLANE
    s = size / 1024.0
    poly = [(p[0] * s, p[1] * s) for p in pts]
    draw.polygon(poly, fill=fill)


def make_icon(
    size: int,
    *,
    top,
    bottom,
    plane_fill=(255, 255, 255, 255),
    style: str = "disc",  # disc | filled | classic | ring
    ring=None,
    square_bg=None,
    alpha_outside: bool = True,
):
    mode_bg = (0, 0, 0, 0) if alpha_outside else (255, 255, 255, 255)
    img = Image.new("RGBA", (size, size), mode_bg)
    draw = ImageDraw.Draw(img)

    if style == "filled":
        # Full-bleed rounded-square feel: solid fill then plane
        if square_bg is not None:
            draw.rectangle([0, 0, size, size], fill=square_bg + (255,))
        else:
            for y in range(size):
                t = y / max(1, size - 1)
                c = lerp(top, bottom, t)
                draw.line([(0, y), (size, y)], fill=c + (255,))
        draw_plane(draw, size, plane_fill, compact=size < 60)
    elif style == "classic":
        # Flat single-color disc (no gradient)
        r = size * 0.82 / 2
        cx = cy = size / 2
        color = top if isinstance(top, tuple) else (40, 170, 230)
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (255,))
        draw_plane(draw, size, plane_fill, compact=size < 60)
    else:
        # disc (default) / ring: optional outer accent ring behind the disc
        if style == "ring" and ring is not None:
            r_out = size * 0.92 / 2
            cx = cy = size / 2
            draw.ellipse(
                [cx - r_out, cy - r_out, cx + r_out, cy + r_out],
                fill=ring + (255,),
            )
            draw_disc(draw, size, top, bottom, ratio=0.78)
        else:
            draw_disc(draw, size, top, bottom, ratio=0.82)
        draw_plane(draw, size, plane_fill, compact=size < 60)

    return img


def save_rgba(img: Image.Image, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG")


def save_rgb(img: Image.Image, path: Path, bg=(255, 255, 255)):
    path.parent.mkdir(parents=True, exist_ok=True)
    rgb = Image.new("RGB", img.size, bg)
    rgb.paste(img, mask=img.split()[3])
    rgb.save(path, "PNG")


# Theme recipes
THEMES = {
    "blue": dict(top=(55, 175, 230), bottom=(30, 145, 210), plane=(255, 255, 255, 255), style="disc"),
    "blue_classic": dict(top=(42, 171, 238), bottom=(42, 171, 238), plane=(255, 255, 255, 255), style="classic"),
    "blue_filled": dict(
        top=(37, 150, 230),
        bottom=(20, 120, 210),
        plane=(255, 255, 255, 255),
        style="filled",
        square_bg=(37, 150, 230),
    ),
    "black": dict(top=(40, 40, 42), bottom=(12, 12, 14), plane=(255, 255, 255, 255), style="disc"),
    "black_classic": dict(top=(28, 28, 30), bottom=(28, 28, 30), plane=(255, 255, 255, 255), style="classic"),
    "black_filled": dict(
        top=(18, 18, 20),
        bottom=(0, 0, 0),
        plane=(255, 255, 255, 255),
        style="filled",
        square_bg=(18, 18, 20),
    ),
    "white_filled": dict(
        top=(245, 247, 250),
        bottom=(230, 235, 240),
        plane=(37, 150, 230, 255),
        style="filled",
        square_bg=(245, 247, 250),
    ),
    "new1": dict(top=(90, 80, 220), bottom=(40, 120, 255), plane=(255, 255, 255, 255), style="disc"),
    "new2": dict(top=(20, 200, 190), bottom=(10, 140, 200), plane=(255, 255, 255, 255), style="disc"),
    "premium": dict(
        top=(255, 210, 120),
        bottom=(210, 150, 50),
        plane=(255, 255, 255, 255),
        style="ring",
        ring=(255, 230, 170),
    ),
    "premium_turbo": dict(
        top=(255, 80, 120),
        bottom=(120, 40, 255),
        plane=(255, 230, 160, 255),
        style="ring",
        ring=(255, 200, 80),
    ),
    "premium_black": dict(
        top=(28, 28, 30),
        bottom=(0, 0, 0),
        plane=(255, 205, 90, 255),
        style="ring",
        ring=(200, 160, 60),
    ),
}


def render(theme_key: str, size: int, alpha_outside: bool = True) -> Image.Image:
    t = THEMES[theme_key]
    return make_icon(
        size,
        top=t["top"],
        bottom=t["bottom"],
        plane_fill=t["plane"],
        style=t["style"],
        ring=t.get("ring"),
        square_bg=t.get("square_bg"),
        alpha_outside=alpha_outside,
    )


def write_alticon_tree(folder: str, theme: str, mapping: list[tuple[str, int, str]]):
    """mapping: (filename, size, 'rgb'|'rgba')"""
    base = ROOT / f"{folder}.alticon"
    for name, size, mode in mapping:
        img = render(theme, size, alpha_outside=(mode == "rgba"))
        path = base / name
        if mode == "rgb":
            # filled white uses light bg; black themes use black paste bg
            bg = (245, 247, 250) if "white" in theme else (0, 0, 0) if "black" in theme or theme.startswith("premium_black") else (255, 255, 255)
            if theme in ("blue", "blue_classic", "blue_filled", "new1", "new2", "premium", "premium_turbo"):
                bg = (255, 255, 255)
            save_rgb(img, path, bg=bg)
        else:
            save_rgba(img, path)


def standard_home_mapping(prefix: str, with_notification: bool = True) -> list[tuple[str, int, str]]:
    items = [
        (f"{prefix}@2x.png", 120, "rgb"),
        (f"{prefix}@3x.png", 180, "rgb"),
        (f"{prefix}Ipad@2x.png", 152, "rgb"),
        (f"{prefix}Ipad.png", 76, "rgb"),
        (f"{prefix}LargeIpad@2x.png", 167, "rgb"),
    ]
    if with_notification:
        # notification names vary: BlueNotificationIcon vs BlueClassicNotificationIcon
        notif = prefix.replace("Icon", "NotificationIcon") if prefix.endswith("Icon") else f"{prefix}NotificationIcon"
        # BlueFilledIcon / BlackFilledIcon / WhiteFilledIcon have no notification assets
        items += [
            (f"{notif}@2x.png", 40, "rgba"),
            (f"{notif}@3x.png", 60, "rgba"),
            (f"{notif}.png", 20, "rgba"),
        ]
    return items


def main():
    # --- Primary / DefaultAppIcon / BlueIcon ---
    for theme, folder, with_notif in [
        ("blue", "BlueIcon", True),
        ("blue_classic", "BlueClassicIcon", True),
        ("blue_filled", "BlueFilledIcon", False),
        ("black", "BlackIcon", True),
        ("black_classic", "BlackClassicIcon", True),
        ("black_filled", "BlackFilledIcon", False),
        ("white_filled", "WhiteFilledIcon", False),
    ]:
        mapping = standard_home_mapping(folder, with_notification=with_notif)
        # Filled sets don't include notification in folder listing for White - only @2x @3x
        if folder == "WhiteFilledIcon":
            mapping = [
                ("WhiteFilledIcon@2x.png", 120, "rgb"),
                ("WhiteFilledIcon@3x.png", 180, "rgb"),
            ]
        if folder == "BlueFilledIcon":
            mapping = [
                ("BlueFilledIcon@2x.png", 120, "rgb"),
                ("BlueFilledIcon@3x.png", 180, "rgb"),
                ("BlueFilledIconIpad@2x.png", 152, "rgb"),
                ("BlueFilledIconIpad.png", 76, "rgb"),
                ("BlueFilledIconLargeIpad@2x.png", 167, "rgb"),
            ]
        if folder == "BlackFilledIcon":
            mapping = [
                ("BlackFilledIcon@2x.png", 120, "rgb"),
                ("BlackFilledIcon@3x.png", 180, "rgb"),
                ("BlackFilledIconIpad@2x.png", 152, "rgba"),
                ("BlackFilledIconIpad.png", 76, "rgb"),
                ("BlackFilledIconLargeIpad@2x.png", 167, "rgb"),
            ]
        write_alticon_tree(folder, theme, mapping)
        print("wrote", folder)

    # New1 / New2 — keep existing filenames
    new1 = [
        ("New1@2x.png", 120),
        ("New1@3x.png", 180),
        ("New1-76.png", 76),
        ("New1-76@2x.png", 152),
        ("New1-83.5@2x.png", 167),
        ("New1_29x29.png", 29),
        ("New1_58x58.png", 58),
        ("New1_80x80.png", 80),
        ("New1_87x87.png", 87),
        ("New1_notification.png", 20),
        ("New1_notification@2x.png", 40),
        ("New1_notification@3x.png", 60),
    ]
    for name, sz in new1:
        save_rgba(render("new1", sz), ROOT / "New1.alticon" / name)
    print("wrote New1")

    new2 = [
        ("New2@2x.png", 120),
        ("New2@3x.png", 180),
        ("New2-76.png", 76),
        ("New2-76@2x.png", 152),
        ("New2-83.5@2x.png", 167),
        ("New2_notification.png", 20),
        ("New2_notification@3x.png", 60),
        ("New2-Small.png", 29),
        ("New2-Small@2x.png", 58),
        ("New2-Small@3x.png", 87),
        ("New2-Small-40.png", 40),
        ("New2-Small-40@2x.png", 80),
    ]
    for name, sz in new2:
        save_rgba(render("new2", sz), ROOT / "New2.alticon" / name)
    print("wrote New2")

    # Premium trio
    for folder, theme in [
        ("Premium", "premium"),
        ("PremiumTurbo", "premium_turbo"),
        ("PremiumBlack", "premium_black"),
    ]:
        for name, sz in [(f"{folder}@2x.png", 120), (f"{folder}@3x.png", 180)]:
            save_rgba(render(theme, sz), ROOT / f"{folder}.alticon" / name)
        print("wrote", folder)

    # DefaultAppIcon
    default = ROOT / "DefaultAppIcon.xcassets/AppIconLLC.appiconset"
    default_map = {
        "Simple-iTunesArtwork.png": 1024,
        "BlueIcon@3x.png": 180,
        "BlueIcon@2x.png": 120,
        "BlueIcon@2x-1.png": 120,
        "BlueIconIpad@2x.png": 152,
        "BlueIconLargeIpad@2x.png": 167,
        "BlueNotificationIcon@3x.png": 60,
        "BlueNotificationIcon@2x.png": 40,
        "BlueNotificationIcon@2x-1.png": 40,
        "BlueNotificationIcon.png": 20,
        "Simple@87x87.png": 87,
        "Simple@80x80.png": 80,
        "Simple@80x80-1.png": 80,
        "Simple@58x58.png": 58,
        "Simple@58x58-1.png": 58,
        "Simple@40x40-1.png": 40,
        "Simple@29x29.png": 29,
    }
    for name, sz in default_map.items():
        save_rgba(render("blue", sz), default / name)
    print("wrote DefaultAppIcon")

    # AppIcons.xcassets — regenerate by size in filename
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
            if not m:
                continue
            save_rgba(render(theme, int(m.group(1))), d / fn)
        print("wrote", set_name)

    # Previews
    for key, label in [
        ("blue", "default"),
        ("premium", "premium"),
        ("premium_turbo", "premium-turbo"),
        ("premium_black", "premium-black"),
        ("new1", "new1"),
        ("black", "black"),
    ]:
        save_rgba(render(key, 1024), ART / f"telegram-icon-{label}-1024.png")

    print("done")


if __name__ == "__main__":
    main()
