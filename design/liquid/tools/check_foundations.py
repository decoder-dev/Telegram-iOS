"""Measure text contrast from the rendered prototype, including placeholders."""

import json
import re
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]


def luminance(color):
    channels = [value / 255 for value in color[:3]]
    linear = [value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4 for value in channels]
    return sum(value * weight for value, weight in zip(linear, [0.2126, 0.7152, 0.0722]))


def color(value):
    parts = [float(number) for number in re.findall(r"[\d.]+", value)]
    return parts + [1] if len(parts) == 3 else parts


def check():
    results = []
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page()
        for theme in ['light', 'dark']:
            for screen, samples in [
                ('02_chats', [('.row-heading strong', None),('.row-preview p', None),('.badge', None),('.avatar', None),('.avatar.gold', None),('.avatar.blue', None),('.avatar.teal', None),('.search-box input','::placeholder')]),
                ('03_chat', [('.message:not(.out) .bubble', None),('.message.out .bubble', None),('.day', None),('#message-input','::placeholder')]),
                ('24_settings', [('.settings-row .row-name', None),('.settings-profile small', None)]),
                ('27_vault_locked', [('.primary',None)]),
            ]:
                page.goto('about:blank')
                page.goto((ROOT/'prototype/index.html').as_uri()+f'#screen={screen}&theme={theme}')
                for selector, pseudo in samples:
                    values = page.locator(selector).first.evaluate("""(element,pseudo) => {
                      const backgrounds=[];
                      for(let ancestor=element;ancestor;ancestor=ancestor.parentElement) backgrounds.unshift(getComputedStyle(ancestor).backgroundColor);
                      return {foreground:getComputedStyle(element,pseudo).color,backgrounds};
                    }""", pseudo)
                    background = [255,255,255]
                    for raw in values['backgrounds']:
                        red,green,blue,alpha = color(raw)
                        background = [front*alpha+back*(1-alpha) for front,back in zip([red,green,blue],background)]
                    foreground = color(values['foreground'])
                    levels = sorted([luminance(foreground),luminance(background)])
                    ratio = (levels[1]+0.05)/(levels[0]+0.05)
                    results.append(dict(theme=theme,screen=screen,selector=selector,pseudo=pseudo,foreground=values['foreground'],background=background,ratio=round(ratio,2),minimum=4.5,status='PASS' if ratio>=4.5 else 'FAIL'))
        browser.close()
    (ROOT/'qa/contrast.json').write_text(json.dumps({'scope':'Static text on flat prototype surfaces; does not measure native glass over arbitrary content.', 'results':results},ensure_ascii=False,indent=2)+'\n')
    failed = [item for item in results if item['status']=='FAIL']
    print(json.dumps({'passed':len(results)-len(failed),'failed':failed},ensure_ascii=False))
    return bool(failed)


if __name__ == '__main__':
    raise SystemExit(check())
