"""Render the BananaGram app icon into every Apple asset slot.

The mark: a broad banana crescent and a folded paper plane, drawn as clean vectors.
21 coordinated palettes; internal icon identifiers stay stable.
Requires Python 3, cairosvg and Pillow.
"""
import io
from functools import lru_cache
import json
from pathlib import Path
import cairosvg
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'Telegram/Telegram-iOS'
OUT = ROOT / 'assets/branding'

YELLOW = ('#FFE68A', '#F4CF57', '#EDC64C')
GOLD = ('#FFE6A0', '#E6BF60', '#DBB55B')
INK = ('#35332B', '#27251F', '#1D1C18')
WHITE_PLANE = ('#FFFEF7', '#DDD8C9')

# Stable bundle identifier: (label, background top/bottom, soft light, crescent, plane/fold).
PALETTES = {
    'BlueIcon': ('Banana', '#FFE486', '#F5C544', '#FFF6D1', INK, ('#29271F', '#514A34')),
    'BlackIcon': ('Graphite', '#34322C', '#1A1916', '#605B4D', YELLOW, WHITE_PLANE),
    'BlueClassicIcon': ('Cream', '#FFFCF5', '#EFE6D1', '#FFFFFF', ('#A1751F', '#896019', '#714A0E'), ('#292D32', '#55534B')),
    'BlackClassicIcon': ('Ink', '#293457', '#11172B', '#5D6A96', YELLOW, WHITE_PLANE),
    'BlueFilledIcon': ('Ocean', '#126A88', '#09425E', '#52ABC2', YELLOW, WHITE_PLANE),
    'BlackFilledIcon': ('Slate', '#59636B', '#30383F', '#97A4AD', YELLOW, WHITE_PLANE),
    'WhiteFilledIcon': ('Paper', '#FFFFFF', '#EBEDE8', '#FFFFFF', INK, ('#344A55', '#667984')),
    'New1': ('Mint', '#BEEED7', '#83CFAD', '#EFFFF6', INK, ('#214C3A', '#497760')),
    'New2': ('Lavender', '#E4DAF8', '#BAA6DF', '#FAF5FF', INK, ('#483957', '#6F5C86')),
    'Premium': ('Gold', '#3B3020', '#201A12', '#87704E', GOLD, ('#FFF0BD', '#D3BA79')),
    'PremiumBlack': ('Noir', '#292929', '#101010', '#595959', ('#FAF8EE', '#E9E5D7', '#C8C3B5'), WHITE_PLANE),
    'PremiumTurbo': ('Volt', '#D5F790', '#A6D755', '#F4FFDC', INK, ('#283322', '#536743')),
    'PremiumNight': ('Midnight', '#3E3777', '#201B43', '#8075C4', YELLOW, WHITE_PLANE),
    'PremiumRose': ('Rose', '#F6CFD7', '#DC9FAF', '#FFF0F3', INK, ('#50333D', '#805665')),
    'PremiumEmerald': ('Emerald', '#236B53', '#123C30', '#71AD91', YELLOW, WHITE_PLANE),
    'PremiumSunset': ('Sunset', '#F6C39A', '#E9987D', '#FFEBDD', INK, ('#4C342E', '#805647')),
    'PremiumIce': ('Ice', '#EEF8FA', '#BEDCE5', '#FFFFFF', INK, ('#284C5B', '#547A8B')),
    'PremiumCarbon': ('Carbon', '#454849', '#232627', '#7A8081', YELLOW, WHITE_PLANE),
    'PremiumRoyal': ('Royal', '#584594', '#30225E', '#A18DD5', GOLD, ('#FFF0C8', '#D4BC87')),
    'PremiumAurora': ('Aurora', '#23645E', '#393664', '#83C6B4', YELLOW, WHITE_PLANE),
    'PatriotPlaneIcon': ('Coral', '#F7B5A4', '#E78F85', '#FFE9E2', INK, ('#513A37', '#805B57')),
}

# --- vector mark --------------------------------------------------------------------------------------
# One broad crescent and one folded plane. No tiny stems, dotted trails or engraved highlights:
# the same silhouette must remain recognisable in a 29 pt settings row and on the Watch.
BANANA = ('M 244 374 C 304 592 553 645 721 419 C 754 374 775 317 786 248 '
          'C 881 575 699 805 462 805 C 303 805 208 662 220 440 Q 224 402 244 374 Z')
PLANE = 'M 300 352 L 661 209 Q 679 202 675 221 L 604 514 L 509 437 L 461 499 L 458 409 Z'
PLANE_FOLD = 'M 458 409 L 661 209 L 509 437 L 461 499 Z'
OFFSET = 'translate(-41 -41) scale(1.08)'


def _defs(name, effects):
    _, top, bottom, glow, (peel1, peel2, peel3), _ = PALETTES[name]
    filters = ''
    if effects:
        filters = ('<filter id="shadow" x="-25%" y="-25%" width="150%" height="150%">'
                   '<feGaussianBlur in="SourceAlpha" stdDeviation="10"/><feOffset dy="12"/>'
                   '<feComponentTransfer><feFuncA type="linear" slope="0.14"/></feComponentTransfer>'
                   '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>')
    return ('<defs>'
            f'<linearGradient id="bg" x1="0" y1="0" x2="0.8" y2="1"><stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>'
            f'<radialGradient id="glow" cx="0.3" cy="0.1" r="0.9"><stop offset="0" stop-color="{glow}" stop-opacity="0.16"/><stop offset="1" stop-color="{glow}" stop-opacity="0"/></radialGradient>'
            f'<linearGradient id="peel" x1="0" y1="0" x2="0.8" y2="1"><stop offset="0" stop-color="{peel1}"/><stop offset="0.55" stop-color="{peel2}"/><stop offset="1" stop-color="{peel3}"/></linearGradient>'
            f'{filters}</defs>')


def _banana(name, effects):
    return f'<g'+(' filter="url(#shadow)"' if effects else '')+f'><path d="{BANANA}" fill="url(#peel)"/></g>'


def _plane(name, effects):
    plane, fold = PALETTES[name][5]
    return ('<g'+(' filter="url(#shadow)"' if effects else '')+'>'
            + f'<path d="{PLANE}" fill="{plane}"/><path d="{PLANE_FOLD}" fill="{fold}"/></g>')


def svg(name):
    """Opaque square master; the launcher supplies its own outer mask."""
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            + _defs(name, True)
            + '<rect width="1024" height="1024" fill="url(#bg)"/><rect width="1024" height="1024" fill="url(#glow)"/>'
            + f'<g transform="{OFFSET}">' + _banana(name, True) + _plane(name, True) + '</g></svg>')


def composer_layer(name, part):
    """Separate, unmasked vectors; iOS supplies the layer lighting and depth."""
    body = _banana(name, False) if part == 'banana' else _plane(name, False)
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            + _defs(name, False) + f'<g transform="{OFFSET}">' + body + '</g></svg>')


@lru_cache(maxsize=256)
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
                'layers': [{'glass': False, 'image-name': 'PaperPlane.svg', 'name': 'Paper plane'}],
                'shadow': {'kind': 'neutral', 'opacity': 0.25},
                'translucency': {'enabled': False, 'value': 1},
            },
            {
                'layers': [{'glass': False, 'image-name': 'Banana.svg', 'name': 'Banana'}],
                'lighting': 'combined',
                'shadow': {'kind': 'layer-color', 'opacity': 0.3},
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

    # Review actual launcher/settings sizes without enlarging them afterwards.
    sizes = Image.new('RGB', (1260, ((len(PALETTES) + 6) // 7) * 145 + 70), '#F5F2E9')
    size_draw = ImageDraw.Draw(sizes)
    size_draw.text((30, 18), 'BananaGram / 60, 40, 29 px', fill='#282A25', font=title)
    for i, (name, (label, *_)) in enumerate(PALETTES.items()):
        x = 30 + (i % 7) * 175
        y = 76 + (i // 7) * 145
        for offset, pixels in [(0, 60), (68, 40), (116, 29)]:
            mask = Image.new('L', (pixels, pixels))
            ImageDraw.Draw(mask).rounded_rectangle((0, 0, pixels-1, pixels-1), radius=pixels*0.22, fill=255)
            sizes.paste(render(name, (pixels, pixels)), (x+offset, y+60-pixels), mask)
        size_draw.text((x, y+72), label, fill='#30332E', font=font)
    sizes.save(OUT / 'sizes.png')
    print(f'Rendered {len(manifest)} Apple assets / {len(PALETTES)} palettes')

if __name__ == '__main__':
    main()
