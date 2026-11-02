"""Keep the handoff palette in sync with the prototype's computed CSS tokens."""

import json
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
ROLES = {
    'background':'--background', 'groupedBackground':'--grouped', 'surface':'--surface',
    'textPrimary':'--text', 'textSecondary':'--secondary', 'separator':'--line',
    'accent':'--accent', 'accentForeground':'--accent-foreground',
    'incomingBubble':'--incoming', 'outgoingBubble':'--outgoing',
    'controlMaterial':'--glass', 'destructive':'--danger',
}


def export():
    themes = {}
    with sync_playwright() as p:
        browser=p.chromium.launch()
        page=browser.new_page()
        for theme in ['light','dark']:
            page.goto('about:blank')
            page.goto((ROOT/'prototype/index.html').as_uri()+f'#screen=03_chat&theme={theme}')
            themes[theme] = {role: page.locator('body').evaluate('(e,name) => getComputedStyle(e).getPropertyValue(name).trim()',css) for role,css in ROLES.items()}
        browser.close()
    tokens = dict(
        version='0.1.0', status='DESIGN_CANDIDATE', canonical_source='prototype/style.css',
        geometry_note='CSS px correspond to design points in the 393×852 concept; native iOS 27 metrics remain unmeasured.',
        color=themes,
        typography=dict(family='SF Pro intended; system fallback in the web prototype', largeTitle=34,profileTitle=20,body=17,secondary=14,footnote=13,caption=11),
        radii=dict(bubble=18,bubbleGroupedCorner=4,settingsGroup=12,composer=23,roundControl='circle'),
        spacing=[4,8,12,16,20,24,32],
        interaction=dict(minimumTarget=44,visibleRoundControl=40,composerMaximumHeight=132),
        accessibility=dict(textContrastMinimum=4.5,largeTextPreviewScale=1.25,reduceTransparency='opaque surface',reduceMotion='disable web animations; native fallback pending'),
    )
    (ROOT/'foundations/tokens.json').write_text(json.dumps(tokens,ensure_ascii=False,indent=2)+'\n')
    print('Exported both theme palettes from rendered CSS.')


if __name__ == '__main__':
    export()
