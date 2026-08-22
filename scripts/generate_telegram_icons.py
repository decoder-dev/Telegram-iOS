#!/usr/bin/env python3
"""Generate a full premium Телеграм paper-plane icon family (high-detail renderer)."""

from __future__ import annotations

import math
import os
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1] / "Telegram" / "Telegram-iOS"
ART = Path("/opt/cursor/artifacts")
ART.mkdir(parents=True, exist_ok=True)

# Messenger plane in 1024 space — folded paper-plane with readable silhouette at small sizes.
PLANE_BODY = [
    (268, 520),
    (710, 345),
    (655, 680),
    (560, 690),
    (470, 625),
    (590, 455),
    (405, 555),
    (300, 555),
]
PLANE_FOLD = [
    (590, 455),
    (710, 345),
    (655, 680),
    (560, 690),
    (470, 625),
]
PLANE_WING = [
    (268, 520),
    (405, 555),
    (300, 555),
]
PLANE_COMPACT_BODY = [
    (290, 530),
    (690, 360),
    (640, 670),
    (555, 678),
    (480, 620),
    (580, 470),
    (420, 555),
    (320, 555),
]
PLANE_COMPACT_FOLD = [
    (580, 470),
    (690, 360),
    (640, 670),
    (555, 678),
    (480, 620),
]
PLANE_COMPACT_WING = [
    (290, 530),
    (420, 555),
    (320, 555),
]


def lerp(a, b, t: float):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def lerp_f(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def scale_points(points, size: int):
    s = size / 1024.0
    return [(p[0] * s, p[1] * s) for p in points]


def radial_disc_colors(y: float, cy: float, r: float, top, bottom, mid=None, mid_t: float = 0.38):
    t = (y - (cy - r)) / (2 * r)
    t = max(0.0, min(1.0, t))
    if mid is not None and t < mid_t:
        local = t / mid_t
        c = lerp(top, mid, local)
    elif mid is not None:
        local = (t - mid_t) / (1.0 - mid_t)
        c = lerp(mid, bottom, local)
    else:
        c = lerp(top, bottom, t)
    return c if len(c) == 4 else (*c, 255)


def draw_disc_detailed(img: Image.Image, top, bottom, ratio: float, mid=None):
    size = img.size[0]
    px = img.load()
    cx = cy = size / 2
    r = size * ratio / 2
    y0, y1 = int(cy - r), int(cy + r) + 1
    for y in range(max(0, y0), min(size, y1)):
        dy = y + 0.5 - cy
        inside = r * r - dy * dy
        if inside <= 0:
            continue
        half = inside ** 0.5
        x0 = int(cx - half)
        x1 = int(cx + half) + 1
        base = radial_disc_colors(y, cy, r, top, bottom, mid=mid)
        for x in range(max(0, x0), min(size, x1)):
            dx = (x + 0.5 - cx) / r
            dy_n = (y + 0.5 - cy) / r
            dist = dx * dx + dy_n * dy_n
            # Specular highlight (upper-left)
            hx, hy = -0.42, -0.48
            spec = math.exp(-(((dx - hx) ** 2) / 0.08 + ((dy_n - hy) ** 2) / 0.06))
            # Rim light (lower-right)
            rim = max(0.0, (dx * 0.55 + dy_n * 0.75 + 0.15))
            rim = min(1.0, rim * rim)
            # Inner vignette
            vign = max(0.0, dist - 0.55) * 0.35
            r_, g_, b_, a_ = base
            r_ = min(255, int(r_ + spec * 55 + rim * 28 - vign * 40))
            g_ = min(255, int(g_ + spec * 55 + rim * 26 - vign * 40))
            b_ = min(255, int(b_ + spec * 58 + rim * 32 - vign * 35))
            px[x, y] = (r_, g_, b_, a_)


def draw_ring_metallic(img: Image.Image, ring_rgb, ratio_outer: float = 0.94, ratio_inner: float = 0.805):
    size = img.size[0]
    px = img.load()
    cx = cy = size / 2
    r_out = size * ratio_outer / 2
    r_in = size * ratio_inner / 2
    for y in range(size):
        for x in range(size):
            dx = x + 0.5 - cx
            dy = y + 0.5 - cy
            d = math.hypot(dx, dy)
            if d > r_out or d < r_in:
                continue
            t = (y / max(1, size - 1))
            highlight = math.exp(-(((x / size) - 0.32) ** 2 / 0.015 + ((y / size) - 0.28) ** 2 / 0.02))
            shadow = max(0.0, (y / size) - 0.62) * 1.8
            rr, gg, bb = ring_rgb
            rr = int(max(0, min(255, rr + highlight * 45 - shadow * 35 + (t - 0.5) * 18)))
            gg = int(max(0, min(255, gg + highlight * 42 - shadow * 32 + (t - 0.5) * 16)))
            bb = int(max(0, min(255, bb + highlight * 48 - shadow * 28 + (t - 0.5) * 20)))
            edge = min(1.0, (d - r_in) / max(1.0, r_out - r_in))
            alpha = int(255 * (0.85 + 0.15 * edge))
            existing = px[x, y]
            if existing[3] == 0:
                px[x, y] = (rr, gg, bb, alpha)
            else:
                # Blend ring over existing disc edge
                er, eg, eb, ea = existing
                a = alpha / 255.0
                px[x, y] = (
                    int(er * (1 - a) + rr * a),
                    int(eg * (1 - a) + gg * a),
                    int(eb * (1 - a) + bb * a),
                    max(ea, alpha),
                )


def draw_plane_detailed(draw: ImageDraw.ImageDraw, size: int, plane_fill, compact: bool = False):
    body = PLANE_COMPACT_BODY if compact else PLANE_BODY
    fold = PLANE_COMPACT_FOLD if compact else PLANE_FOLD
    wing = PLANE_COMPACT_WING if compact else PLANE_WING
    body_pts = scale_points(body, size)
    fold_pts = scale_points(fold, size)
    wing_pts = scale_points(wing, size)

    shadow_offset = max(1, size // 128)
    shadow_fill = (0, 0, 0, int(plane_fill[3] * 0.22 if len(plane_fill) == 4 else 56))
    shadow_pts = [(x + shadow_offset, y + shadow_offset) for x, y in body_pts]
    draw.polygon(shadow_pts, fill=shadow_fill)

    draw.polygon(body_pts, fill=plane_fill)

    # Fold facet — slightly darker
    if len(plane_fill) == 4:
        fold_fill = (
            max(0, plane_fill[0] - 18),
            max(0, plane_fill[1] - 18),
            max(0, plane_fill[2] - 18),
            plane_fill[3],
        )
        wing_fill = (
            min(255, plane_fill[0] + 12),
            min(255, plane_fill[1] + 12),
            min(255, plane_fill[2] + 12),
            int(plane_fill[3] * 0.92),
        )
    else:
        fold_fill = tuple(max(0, c - 18) for c in plane_fill[:3]) + (255,)
        wing_fill = tuple(min(255, c + 12) for c in plane_fill[:3]) + (235,)

    draw.polygon(fold_pts, fill=fold_fill)
    draw.polygon(wing_pts, fill=wing_fill)

    # Crease highlight stroke
    if size >= 40:
        crease_w = max(1, size // 256)
        crease_color = (255, 255, 255, 120 if len(plane_fill) == 4 else 255)
        p1, p2 = fold_pts[0], fold_pts[1]
        draw.line([p1, p2], fill=crease_color, width=crease_w)


def make_icon(
    size: int,
    *,
    top,
    bottom,
    plane_fill=(255, 255, 255, 255),
    ring=None,
    style: str = "premium",
    square_bg=None,
    alpha_outside: bool = True,
    soft_glow: bool = False,
):
    ss = 4 if size <= 48 else (3 if size <= 120 else (2 if size <= 240 else 1))
    work_size = size * ss
    img = Image.new("RGBA", (work_size, work_size), (0, 0, 0, 0) if alpha_outside else (255, 255, 255, 255))
    draw = ImageDraw.Draw(img)
    compact = work_size < 60 * ss

    mid = tuple(int((top[i] + bottom[i]) / 2) for i in range(3))

    if style == "filled":
        if square_bg is not None:
            draw.rectangle([0, 0, work_size - 1, work_size - 1], fill=(*square_bg, 255))
        else:
            for y in range(work_size):
                c = lerp(top, bottom, y / max(1, work_size - 1))
                draw.line([(0, y), (work_size, y)], fill=(*c, 255))
        draw_disc_detailed(img, top, bottom, ratio=0.78, mid=mid)
        if ring is not None:
            draw_ring_metallic(img, ring, ratio_outer=0.92, ratio_inner=0.79)
        draw_plane_detailed(draw, work_size, plane_fill, compact=compact)
    else:
        if ring is not None:
            draw_ring_metallic(img, ring, ratio_outer=0.94, ratio_inner=0.805)
        draw_disc_detailed(img, top, bottom, ratio=0.80, mid=mid)
        draw_plane_detailed(draw, work_size, plane_fill, compact=compact)

    if ss > 1:
        img = img.resize((size, size), Image.LANCZOS)

    if soft_glow and size >= 120:
        glow = img.filter(ImageFilter.GaussianBlur(radius=max(1, size // 48)))
        base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        base = Image.alpha_composite(base, glow)
        base = Image.alpha_composite(base, img)
        return base
    return img


# All themes are premium-grade. ring colors are champagne / metal accents.
THEMES = {
    "blue": dict(top=(78, 192, 252), bottom=(16, 108, 210), plane=(255, 255, 255, 255), ring=(188, 224, 255)),
    "blue_classic": dict(top=(62, 182, 246), bottom=(22, 124, 212), plane=(255, 255, 255, 255), ring=(172, 214, 250)),
    "blue_filled": dict(
        top=(48, 168, 238), bottom=(12, 102, 198), plane=(255, 255, 255, 255),
        ring=(165, 205, 255), style="filled", square_bg=(14, 86, 172),
    ),
    "black": dict(top=(52, 52, 56), bottom=(4, 4, 6), plane=(255, 255, 255, 255), ring=(175, 178, 188)),
    "black_classic": dict(top=(44, 44, 48), bottom=(10, 10, 12), plane=(255, 255, 255, 255), ring=(158, 160, 172)),
    "black_filled": dict(
        top=(38, 38, 42), bottom=(0, 0, 0), plane=(255, 255, 255, 255),
        ring=(138, 140, 152), style="filled", square_bg=(8, 8, 10),
    ),
    "white_filled": dict(
        top=(252, 252, 255), bottom=(228, 234, 244), plane=(24, 136, 228, 255),
        ring=(215, 195, 135), style="filled", square_bg=(244, 246, 252),
    ),
    "new1": dict(top=(128, 104, 255), bottom=(36, 86, 255), plane=(255, 255, 255, 255), ring=(205, 198, 255)),
    "new2": dict(top=(44, 224, 212), bottom=(8, 124, 198), plane=(255, 255, 255, 255), ring=(175, 238, 228)),
    "premium": dict(top=(255, 224, 148), bottom=(196, 132, 32), plane=(255, 255, 255, 255), ring=(255, 232, 178)),
    "premium_turbo": dict(top=(255, 92, 148), bottom=(104, 36, 255), plane=(255, 228, 158, 255), ring=(255, 198, 88)),
    "premium_black": dict(top=(38, 38, 42), bottom=(0, 0, 0), plane=(255, 202, 88, 255), ring=(205, 165, 62)),
    "premium_night": dict(top=(32, 54, 118), bottom=(4, 8, 36), plane=(218, 228, 255, 255), ring=(132, 162, 255)),
    "premium_rose": dict(top=(255, 182, 192), bottom=(186, 76, 118), plane=(255, 255, 255, 255), ring=(255, 208, 198)),
    "premium_emerald": dict(top=(64, 214, 162), bottom=(8, 106, 86), plane=(255, 244, 208, 255), ring=(198, 228, 158)),
    "premium_sunset": dict(top=(255, 172, 78), bottom=(218, 46, 88), plane=(255, 255, 255, 255), ring=(255, 206, 136)),
    "premium_ice": dict(top=(224, 246, 255), bottom=(96, 168, 232), plane=(255, 255, 255, 255), ring=(228, 244, 255)),
    "premium_carbon": dict(top=(58, 58, 62), bottom=(12, 12, 16), plane=(72, 228, 255, 255), ring=(72, 198, 218)),
    "premium_royal": dict(top=(114, 68, 204), bottom=(36, 12, 88), plane=(255, 216, 118, 255), ring=(215, 175, 86)),
    "premium_aurora": dict(top=(82, 255, 198), bottom=(176, 56, 222), plane=(255, 255, 255, 255), ring=(198, 252, 228)),
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
        soft_glow=(size >= 1024),
    )


def save_rgba(img: Image.Image, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG", optimize=True)


def save_rgb(img: Image.Image, path: Path, bg=(255, 255, 255)):
    path.parent.mkdir(parents=True, exist_ok=True)
    rgb = Image.new("RGB", img.size, bg)
    rgb.paste(img, mask=img.split()[3])
    rgb.save(path, "PNG", optimize=True)


def write_mapping(folder: str, theme: str, mapping: list[tuple[str, int, str]]):
    base = ROOT / f"{folder}.alticon"
    for name, size, mode in mapping:
        img = render(theme, size, alpha_outside=(mode == "rgba"))
        path = base / name
        if mode == "rgb":
            bg = (0, 0, 0) if any(k in theme for k in ("black", "carbon", "night", "royal")) else (255, 255, 255)
            if "white" in theme or "ice" in theme:
                bg = (245, 247, 252)
            save_rgb(img, path, bg=bg)
        else:
            save_rgba(img, path)


def premium_only_mapping(name: str) -> list[tuple[str, int, str]]:
    return [(f"{name}@2x.png", 120, "rgba"), (f"{name}@3x.png", 180, "rgba")]


def main():
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
