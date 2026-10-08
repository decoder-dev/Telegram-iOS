"""Render BananaGram's original vector mark into existing Apple asset slots.
Requires Python 3, cairosvg and Pillow. Existing icon identifiers stay stable.
"""
import io
import json
from pathlib import Path
import cairosvg
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'Telegram/Telegram-iOS'
OUT = ROOT / 'assets/branding'
PALETTES = {
 'BlueIcon': ('Banana', '#FFE56A', '#FFC52E', '#29271D'),
 'BlackIcon': ('Graphite', '#2B2E32', '#111416', '#FFE16A'),
 'BlueClassicIcon': ('Cream', '#FFF9E9', '#F1E6CC', '#6C5420'),
 'BlackClassicIcon': ('Ink', '#171D2E', '#0B1020', '#E7ECFA'),
 'BlueFilledIcon': ('Ocean', '#5FE1EE', '#229FC7', '#123A50'),
 'BlackFilledIcon': ('Slate', '#75868A', '#435156', '#F5EEDC'),
 'WhiteFilledIcon': ('Paper', '#FFFFFF', '#EBEFF2', '#22282D'),
 'New1': ('Mint', '#BCF3D4', '#6ED5B0', '#143F35'),
 'New2': ('Lavender', '#E0CFFF', '#B098E5', '#3B265D'),
 'Premium': ('Gold', '#EED5A0', '#BC8843', '#342619'),
 'PremiumBlack': ('Noir', '#1C1C1C', '#050505', '#DCC698'),
 'PremiumTurbo': ('Volt', '#E8FF78', '#B4DE32', '#29370E'),
 'PremiumNight': ('Midnight', '#303B62', '#141A35', '#DDDAFF'),
 'PremiumRose': ('Rose', '#FFD2D9', '#EA96AE', '#622A42'),
 'PremiumEmerald': ('Emerald', '#248B73', '#064A42', '#D5F2AD'),
 'PremiumSunset': ('Sunset', '#FFC980', '#F37A67', '#6D2934'),
 'PremiumIce': ('Ice', '#E5FAFF', '#A9D3E9', '#244E6B'),
 'PremiumCarbon': ('Carbon', '#585957', '#242624', '#D5DFD2'),
 'PremiumRoyal': ('Royal', '#8E76D6', '#4C348D', '#F7DB94'),
 'PremiumAurora': ('Aurora', '#AFECDE', '#80A4E8', '#293D60'),
 'PatriotPlaneIcon': ('Coral', '#FFAF95', '#E46C5D', '#542B2C'),
}
MARK = 'M 267 254 C 203 415 255 617 398 705 C 534 789 700 739 776 609 C 839 502 840 381 789 272 C 799 423 711 554 588 587 C 456 623 326 528 298 392 C 289 348 290 302 305 270 Q 291 243 267 254 Z'

def svg(name, foreground_only=False):
    _, top, bottom, ink = PALETTES[name]
    background = '' if foreground_only else f'<defs><linearGradient id="bg" x2="0.7" y2="1"><stop stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient></defs><rect width="1024" height="1024" fill="url(#bg)"/>'
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">{background}<g transform="rotate(-28 512 512)"><path d="{MARK}" fill="{ink}"/><path d="M 339 531 C 398 665 579 728 711 616" fill="none" stroke="{top}" stroke-opacity="0.32" stroke-width="14" stroke-linecap="round"/></g></svg>'

def render(name, size):
    return Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg(name).encode(), output_width=size[0]*2, output_height=size[1]*2))).convert('RGB').resize(size, Image.Resampling.LANCZOS)

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = []
    groups = []
    for folder in sorted(APP.glob('*.alticon')):
        if folder.stem in PALETTES: groups.append((folder, folder.stem))
    for folder in (APP/'AppIcons.xcassets').glob('*.appiconset'):
        groups.append((folder, folder.stem))
    groups.append((APP/'DefaultAppIcon.xcassets/AppIconLLC.appiconset', 'BlueIcon'))
    groups += [(p, 'BlueIcon') for p in (ROOT/'Telegram').glob('Watch*/**/AppIcon.appiconset')]
    for folder, name in groups:
        for path in sorted(folder.glob('*.png')):
            with Image.open(path) as old: size = old.size
            render(name, size).save(path, optimize=True)
            manifest.append({'file':path.relative_to(ROOT).as_posix(), 'size':list(size), 'palette':name})
    for name in PALETTES:
        (OUT/f'{name}.svg').write_text(svg(name), encoding='utf-8', newline='\n')
    # Icon Composer keeps the mark separate for Apple's appearance rendering.
    (APP/'Telegram.icon/Assets/Plane.svg').write_text(svg('BlueIcon', True),encoding='utf-8', newline='\n')
    config = json.loads((APP/'Telegram.icon/icon.json').read_text())
    config['fill'] = {'solid':'srgb:1.00000,0.83137,0.21961,1.00000'}
    layer = config['groups'][0]['layers'][0]
    layer['name'] = 'BananaGram'
    layer['glass'] = False
    layer.pop('position-specializations',None)
    layer.pop('fill-specializations',None)
    config['groups'][0]['layers'] = [layer]
    (APP/'Telegram.icon/icon.json').write_text(json.dumps(config,indent=2)+'\n',encoding='utf-8', newline='\n')
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8', newline='\n')
    sheet=Image.new('RGB',(1260, ((len(PALETTES)+6)//7)*215+80),'#F5F2E9')
    draw=ImageDraw.Draw(sheet)
    font_path = next((str(p) for p in [Path('C:/Windows/Fonts/segoeui.ttf'), Path('/System/Library/Fonts/Supplemental/Arial.ttf'), Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')] if p.exists()), None)
    font=ImageFont.truetype(font_path,18) if font_path else ImageFont.load_default(size=18)
    title=ImageFont.truetype(font_path,28) if font_path else ImageFont.load_default(size=28)
    draw.text((30,20),'BananaGram / App icon collection',fill='#282A25',font=title)
    for i,(name,(label,*_)) in enumerate(PALETTES.items()):
        x=30+(i%7)*175; y=80+(i//7)*215
        icon=render(name,(140,140))
        mask=Image.new('L',(140,140)); ImageDraw.Draw(mask).rounded_rectangle((0,0,139,139),radius=31,fill=255)
        sheet.paste(icon,(x,y),mask)
        draw.text((x,y+152),label,fill='#30332E',font=font)
    sheet.save(OUT/'preview.png')
    print(f'Rendered {len(manifest)} Apple assets / {len(PALETTES)} palettes')
if __name__=='__main__': main()
