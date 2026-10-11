"""Render the BananaGram app icon into every Apple asset slot.

The mark: a glossy banana built from an offset centre curve (so its edges stay smooth at every size), with
a Telegram paper plane taking off from its curve. 21 palettes; internal icon identifiers stay stable.
Requires Python 3, cairosvg and Pillow.
"""
import io
import json
import math
from pathlib import Path
import cairosvg
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'Telegram/Telegram-iOS'
OUT = ROOT / 'assets/branding'

YELLOW = ('#FFF5B0', '#FFD21F', '#E08E00')
GOLD = ('#FFFBE0', '#FFD86A', '#C2861A')
WHITE_PLANE = ('#FFFFFF', '#D4E2EE')

# name: (label, background top, background bottom, glow, peel, plane)
PALETTES = {
    'BlueIcon': ('Banana', '#3CC2FF', '#0A6CFF', '#B3ECFF', YELLOW, WHITE_PLANE),
    'BlackIcon': ('Graphite', '#3B3934', '#121110', '#7A7058', YELLOW, ('#FFFFFF', '#D8D2C2')),
    'BlueClassicIcon': ('Cream', '#FFF9EA', '#F0DBA6', '#FFFFFF', YELLOW, ('#2B2A26', '#0F0E0B')),
    'BlackClassicIcon': ('Ink', '#1E2748', '#070A16', '#4A63C9', YELLOW, ('#FFFFFF', '#C9D2F0')),
    'BlueFilledIcon': ('Ocean', '#36E0E8', '#0B6FA8', '#B9FBFF', YELLOW, ('#FFFFFF', '#CBE9F2')),
    'BlackFilledIcon': ('Slate', '#7A8894', '#2F3942', '#C4D0DA', YELLOW, ('#FFFFFF', '#D3DBE2')),
    'WhiteFilledIcon': ('Paper', '#FFFFFF', '#E3E8EE', '#FFFFFF', YELLOW, ('#2AABEE', '#1C86C2')),
    'New1': ('Mint', '#A8F5D2', '#1FB282', '#E8FFF5', YELLOW, ('#FFFFFF', '#C9F0DF')),
    'New2': ('Lavender', '#DCCBFF', '#8763EE', '#F4EEFF', YELLOW, ('#FFFFFF', '#DCD2F7')),
    'Premium': ('Gold', '#3A2A0C', '#120B02', '#A8803A', GOLD, ('#FFE7A8', '#D2AE58')),
    'PremiumBlack': ('Noir', '#262626', '#000000', '#5A5A5A', YELLOW, ('#FFFFFF', '#CFCFCF')),
    'PremiumTurbo': ('Volt', '#D2FF4A', '#32A800', '#F4FFC0', YELLOW, ('#16230A', '#050A02')),
    'PremiumNight': ('Midnight', '#3A30A0', '#0D0A2C', '#7C6CFF', YELLOW, ('#FFFFFF', '#CFC9F5')),
    'PremiumRose': ('Rose', '#FFB3C7', '#DF4079', '#FFE6EE', YELLOW, ('#FFFFFF', '#F6D3DE')),
    'PremiumEmerald': ('Emerald', '#1FA67A', '#03432E', '#7CF0C0', YELLOW, ('#FFFFFF', '#BFE8D6')),
    'PremiumSunset': ('Sunset', '#FFB36B', '#E5396A', '#FFE1B0', YELLOW, ('#FFFFFF', '#F8D5C9')),
    'PremiumIce': ('Ice', '#F4FCFF', '#9FD8F4', '#FFFFFF', YELLOW, ('#1D4E6E', '#0E3048')),
    'PremiumCarbon': ('Carbon', '#4E4E4E', '#141414', '#8A8A8A', YELLOW, ('#FFFFFF', '#CFCFCF')),
    'PremiumRoyal': ('Royal', '#7A5CFF', '#260C8A', '#B9A8FF', GOLD, ('#FFE38A', '#D2AA3E')),
    'PremiumAurora': ('Aurora', '#14E0B0', '#6A48FF', '#C2FFF0', YELLOW, ('#FFFFFF', '#D7D0FA')),
    'PatriotPlaneIcon': ('Coral', '#FF9A86', '#EE4258', '#FFE0D8', YELLOW, ('#FFFFFF', '#F8D2CF')),
}

# --- geometry -----------------------------------------------------------------------------------------
P = [(188, 560), (300, 860), (760, 840), (770, 300)]   # centre curve, blossom tip -> stem
MAXW = 170

def _point(t):
    u = 1 - t
    return tuple(u**3*P[0][i] + 3*u*u*t*P[1][i] + 3*u*t*t*P[2][i] + t**3*P[3][i] for i in (0, 1))

def _derivatives(t):
    u = 1 - t
    d = tuple(3*u*u*(P[1][i]-P[0][i]) + 6*u*t*(P[2][i]-P[1][i]) + 3*t*t*(P[3][i]-P[2][i]) for i in (0, 1))
    dd = tuple(6*u*(P[2][i]-2*P[1][i]+P[0][i]) + 6*t*(P[3][i]-2*P[2][i]+P[1][i]) for i in (0, 1))
    return d, dd

def _tangent(t):
    (dx, dy), _ = _derivatives(t)
    length = math.hypot(dx, dy)
    return dx/length, dy/length

def _radius(t):
    (dx, dy), (ddx, ddy) = _derivatives(t)
    k = abs(dx*ddy - dy*ddx) / (dx*dx + dy*dy) ** 1.5
    return 1e9 if k < 1e-9 else 1/k

def _width(t):
    a = 0.18 + 0.82 * min(1, t / 0.24) ** 0.7       # blossom end
    b = min(1, (1 - t) / 0.30) ** 0.85               # narrowing into the stem
    return MAXW * a * (0.30 + 0.70 * b)

def _smooth(pts, passes=10, k=4):
    for _ in range(passes):
        n = len(pts)
        out = []
        for i in range(n):
            if i < 2 or i > n - 3:
                out.append(pts[i]); continue
            a, b = max(0, i - k), min(n, i + k + 1)
            out.append((sum(p[0] for p in pts[a:b]) / (b - a), sum(p[1] for p in pts[a:b]) / (b - a)))
        pts = out
    return pts

def _side(sign, scale=1.0, t0=0.0, t1=1.0, n=160):
    pts = []
    for i in range(n + 1):
        t = t0 + (t1 - t0) * i / n
        x, y = _point(t); tx, ty = _tangent(t)
        nx, ny = ty, -tx                              # towards the inner (concave) side
        w = _width(t) / 2
        if sign > 0:
            w = min(w, 0.8 * _radius(t))              # keeps the inner edge from folding at the bend
        pts.append((x + nx * sign * w * scale, y + ny * sign * w * scale))
    return _smooth(pts)

def _area(a, b):
    pts = a + list(reversed(b))
    return 'M ' + ' L '.join(f'{x:.1f} {y:.1f}' for x, y in pts) + ' Z'

def _line(pts):
    return 'M ' + ' L '.join(f'{x:.1f} {y:.1f}' for x, y in pts)

BODY = _area(_side(+1), _side(-1))
UNDER = _area(_side(-0.15), _side(-1))
HIGH = _area(_side(+1, 0.92, 0.12, 0.86), _side(+1, 0.55, 0.12, 0.86))
RIDGE = _line(_side(-1, 0.38, 0.10, 0.93))
RIDGE2 = _line(_side(+1, 0.18, 0.16, 0.90))

def _stem():
    sx, sy = _point(1.0); tx, ty = _tangent(1.0)
    w0 = _width(1.0) / 2 * 0.95
    a, b = [], []
    for i in range(11):
        k = i / 10
        length, bend = 78 * k, 10 * k * k
        x, y = sx + tx*length + ty*bend, sy + ty*length - tx*bend
        w = w0 * (1 - 0.35 * k)
        a.append((x + ty*w, y - tx*w)); b.append((x - ty*w, y + tx*w))
    cap = f'M {a[-1][0]:.1f} {a[-1][1]:.1f} L {b[-1][0]:.1f} {b[-1][1]:.1f} L {b[-1][0]+tx*14:.1f} {b[-1][1]+ty*14:.1f} L {a[-1][0]+tx*14:.1f} {a[-1][1]+ty*14:.1f} Z'
    return _area(a, b), cap
STEM, CAP = _stem()

def _tip():
    x, y = _point(0.0); tx, ty = _tangent(0.0)
    return f'M {x+ty*16:.1f} {y-tx*16:.1f} L {x-tx*22:.1f} {y-ty*22:.1f} L {x-ty*16:.1f} {y+tx*16:.1f} Z'
TIP = _tip()

PLANE = 'M 0 120 L 250 20 L 200 230 L 130 175 L 110 230 L 95 160 Z'
PLANE_FOLD = 'M 95 160 L 250 20 L 130 175 L 110 230 Z'
PLANE_TRANSFORM = 'translate(348 220) rotate(-12) scale(1.04)'
TRAIL = 'M 268 554 C 288 464 318 404 378 366'
OFFSET = 'translate(18 -6)'

# --- rendering ----------------------------------------------------------------------------------------
def _defs(name, effects):
    _, top, bottom, glow, (peel1, peel2, peel3), (plane, _) = PALETTES[name]
    filters = ''
    if effects:
        filters = ('<filter id="shadow" x="-25%" y="-25%" width="150%" height="160%"><feGaussianBlur in="SourceAlpha" stdDeviation="24"/>'
                   '<feOffset dy="30"/><feComponentTransfer><feFuncA type="linear" slope="0.38"/></feComponentTransfer>'
                   '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>'
                   '<filter id="pshadow" x="-40%" y="-40%" width="180%" height="190%"><feGaussianBlur in="SourceAlpha" stdDeviation="12"/>'
                   '<feOffset dy="14"/><feComponentTransfer><feFuncA type="linear" slope="0.32"/></feComponentTransfer>'
                   '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>')
    return ('<defs>'
            f'<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>'
            f'<radialGradient id="glow" cx="0.30" cy="0.22" r="0.8"><stop offset="0" stop-color="{glow}" stop-opacity="0.55"/><stop offset="1" stop-color="{glow}" stop-opacity="0"/></radialGradient>'
            f'<linearGradient id="peel" x1="0.25" y1="0.2" x2="0.7" y2="1"><stop offset="0" stop-color="{peel1}"/><stop offset="0.5" stop-color="{peel2}"/><stop offset="1" stop-color="{peel3}"/></linearGradient>'
            f'<linearGradient id="under" x1="0" y1="0" x2="0.4" y2="1"><stop offset="0" stop-color="{peel3}" stop-opacity="0"/><stop offset="1" stop-color="{peel3}" stop-opacity="0.85"/></linearGradient>'
            '<linearGradient id="hi" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFFFFF" stop-opacity="0.9"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0.15"/></linearGradient>'
            '<linearGradient id="stemg" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#9DB23C"/><stop offset="1" stop-color="#5E7224"/></linearGradient>'
            f'<linearGradient id="trail" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="{plane}" stop-opacity="0"/><stop offset="1" stop-color="{plane}" stop-opacity="0.55"/></linearGradient>'
            f'{filters}</defs>')

def _banana(name, effects):
    peel3 = PALETTES[name][4][2]
    s = '<g filter="url(#shadow)">' if effects else '<g>'
    s += f'<path d="{STEM}" fill="url(#stemg)"/><path d="{CAP}" fill="#4A3418" stroke="#4A3418" stroke-width="6" stroke-linejoin="round"/>'
    s += f'<path d="{BODY}" fill="url(#peel)"/><path d="{UNDER}" fill="url(#under)"/>'
    s += f'<path d="{RIDGE}" fill="none" stroke="{peel3}" stroke-opacity="0.45" stroke-width="7" stroke-linecap="round"/>'
    s += f'<path d="{RIDGE2}" fill="none" stroke="#FFFFFF" stroke-opacity="0.25" stroke-width="5" stroke-linecap="round"/>'
    s += f'<path d="{HIGH}" fill="url(#hi)" opacity="0.75"/><path d="{TIP}" fill="#4A3418"/></g>'
    return s

def _plane(name, effects):
    plane, fold = PALETTES[name][5]
    s = f'<path d="{TRAIL}" fill="none" stroke="url(#trail)" stroke-width="12" stroke-linecap="round" stroke-dasharray="2 26"/>'
    s += f'<g{" filter=\"url(#pshadow)\"" if effects else ""} transform="{PLANE_TRANSFORM}"><path d="{PLANE}" fill="{plane}"/><path d="{PLANE_FOLD}" fill="{fold}"/></g>'
    return s

def svg(name):
    """Full icon with background, shadows and glow (alternate icons, catalogs, previews)."""
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            + _defs(name, True)
            + '<rect width="1024" height="1024" fill="url(#bg)"/><rect width="1024" height="1024" fill="url(#glow)"/>'
            + f'<g transform="{OFFSET}">' + _banana(name, True) + _plane(name, True) + '</g></svg>')

def composer_layer(name, part):
    """Icon Composer layer: no filters and no background; the system adds depth, shadow and glass."""
    body = _banana(name, False) if part == 'banana' else _plane(name, False)
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            + _defs(name, False) + f'<g transform="{OFFSET}">' + body + '</g></svg>')

def render(name, size):
    png = cairosvg.svg2png(bytestring=svg(name).encode(), output_width=size[0]*2, output_height=size[1]*2)
    return Image.open(io.BytesIO(png)).convert('RGB').resize(size, Image.Resampling.LANCZOS)

def _srgb(hex_color):
    r, g, b = (int(hex_color[i:i+2], 16) / 255 for i in (1, 3, 5))
    return f'srgb:{r:.5f},{g:.5f},{b:.5f},1.00000'

def write_composer_icon():
    folder = APP / 'Telegram.icon'
    assets = folder / 'Assets'
    for old in assets.glob('*.svg'):
        old.unlink()
    (assets / 'Banana.svg').write_text(composer_layer('BlueIcon', 'banana'), encoding='utf-8', newline='\n')
    (assets / 'PaperPlane.svg').write_text(composer_layer('BlueIcon', 'plane'), encoding='utf-8', newline='\n')
    _, top, bottom, *_ = PALETTES['BlueIcon']
    config = {
        'fill': {
            'linear-gradient': [_srgb(top), _srgb(bottom)],
            'orientation': {'start': {'x': 0.2, 'y': 0}, 'stop': {'x': 0.8, 'y': 1}},
        },
        'groups': [
            {
                'layers': [{'glass': True, 'image-name': 'PaperPlane.svg', 'name': 'Paper plane'}],
                'shadow': {'kind': 'neutral', 'opacity': 0.5},
                'translucency': {'enabled': True, 'value': 0.4},
            },
            {
                'layers': [{'glass': False, 'image-name': 'Banana.svg', 'name': 'Banana'}],
                'lighting': 'combined',
                'shadow': {'kind': 'layer-color', 'opacity': 0.6},
                'specular': True,
                'translucency': {'enabled': False, 'value': 1},
            },
        ],
        'supported-platforms': {'circles': ['watchOS'], 'squares': 'shared'},
    }
    (folder / 'icon.json').write_text(json.dumps(config, indent=2) + '\n', encoding='utf-8', newline='\n')

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = []
    groups = []
    for folder in sorted(APP.glob('*.alticon')):
        if folder.stem in PALETTES:
            groups.append((folder, folder.stem))
    for folder in sorted((APP / 'AppIcons.xcassets').glob('*.appiconset')):
        groups.append((folder, folder.stem))
    groups.append((APP / 'DefaultAppIcon.xcassets/AppIconLLC.appiconset', 'BlueIcon'))
    groups += [(p, 'BlueIcon') for p in sorted((ROOT / 'Telegram').glob('Watch*/**/AppIcon.appiconset'))]
    loose = sorted(APP.glob('IconDefault*.png'))
    for folder, name in groups:
        for path in sorted(folder.glob('*.png')):
            with Image.open(path) as old:
                size = old.size
            render(name, size).save(path, optimize=True)
            manifest.append({'file': path.relative_to(ROOT).as_posix(), 'size': list(size), 'palette': name})
    for path in loose:
        with Image.open(path) as old:
            size = old.size
        render('BlueIcon', size).save(path, optimize=True)
        manifest.append({'file': path.relative_to(ROOT).as_posix(), 'size': list(size), 'palette': 'BlueIcon'})
    for name in PALETTES:
        (OUT / f'{name}.svg').write_text(svg(name), encoding='utf-8', newline='\n')
    write_composer_icon()
    (OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8', newline='\n')

    sheet = Image.new('RGB', (1260, ((len(PALETTES) + 6) // 7) * 215 + 80), '#F5F2E9')
    draw = ImageDraw.Draw(sheet)
    font_path = next((str(p) for p in [Path('C:/Windows/Fonts/segoeui.ttf'), Path('/System/Library/Fonts/Supplemental/Arial.ttf'), Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')] if p.exists()), None)
    font = ImageFont.truetype(font_path, 18) if font_path else ImageFont.load_default(size=18)
    title = ImageFont.truetype(font_path, 28) if font_path else ImageFont.load_default(size=28)
    draw.text((30, 20), 'BananaGram / App icon collection', fill='#282A25', font=title)
    for i, (name, (label, *_)) in enumerate(PALETTES.items()):
        x = 30 + (i % 7) * 175
        y = 80 + (i // 7) * 215
        icon = render(name, (140, 140))
        mask = Image.new('L', (140, 140))
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, 139, 139), radius=31, fill=255)
        sheet.paste(icon, (x, y), mask)
        draw.text((x, y + 152), label, fill='#30332E', font=font)
    sheet.save(OUT / 'preview.png')
    print(f'Rendered {len(manifest)} Apple assets / {len(PALETTES)} palettes')

if __name__ == '__main__':
    main()
