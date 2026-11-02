"""Export the three reference compositions as editable SVG and 3× PNG."""

from pathlib import Path
import json
import struct
import xml.etree.ElementTree as ET
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
EXPORT = ROOT / "mockups"

# Export layout geometry, vector icons and text. No screenshot is embedded in the SVG.
SVG_EXPORT = r"""root => {
  const box = root.getBoundingClientRect();
  const ns = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(ns, 'svg');
  svg.setAttribute('xmlns', ns);
  svg.setAttribute('width', box.width); svg.setAttribute('height', box.height);
  svg.setAttribute('viewBox', `0 0 ${box.width} ${box.height}`);
  const defs = document.createElementNS(ns, 'defs'); svg.append(defs);
  const canvas = document.createElement('canvas').getContext('2d');
  let serial = 0;
  const node = (tag, attributes) => {
    const n = document.createElementNS(ns, tag);
    for (const [key,value] of Object.entries(attributes)) n.setAttribute(key,value);
    return n;
  };
  function text(parent, textNode, style) {
    const text = textNode.textContent;
    const lines = [];
    for (let i=0; i<text.length; i++) {
      const range = document.createRange(); range.setStart(textNode,i); range.setEnd(textNode,i+1);
      const r = range.getBoundingClientRect();
      if (!r.width || !r.height) continue;
      let line = lines.at(-1);
      if (!line || Math.abs(line.y-r.top)>1) { line={x:r.left,y:r.top,height:r.height,text:''}; lines.push(line); }
      line.text += text[i];
    }
    canvas.font = `${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
    const metrics = canvas.measureText('Ag');
    for (const line of lines) {
      const label = node('text',{x:line.x-box.x,y:line.y-box.y+metrics.fontBoundingBoxAscent,'font-family':style.fontFamily,'font-size':style.fontSize,'font-weight':style.fontWeight,fill:style.color});
      label.textContent = style.textTransform==='uppercase' ? line.text.toUpperCase() : line.text;
      parent.append(label);
    }
  }
  function visit(element,parent) {
    const style = getComputedStyle(element);
    const r = element.getBoundingClientRect();
    if (style.display==='none' || style.visibility==='hidden' || Number(style.opacity)===0 || r.width<=1 || r.height<=1 || element.classList.contains('sr-only')) return;
    const x=r.x-box.x, y=r.y-box.y;
    if (element.tagName.toLowerCase()==='svg') {
      const copy=element.cloneNode(true);
      copy.setAttribute('x',x);copy.setAttribute('y',y);copy.setAttribute('width',r.width);copy.setAttribute('height',r.height);
      copy.setAttribute('color',style.color); copy.setAttribute('fill',style.fill);copy.setAttribute('stroke',style.stroke);
      copy.setAttribute('stroke-width',style.strokeWidth);copy.setAttribute('stroke-linecap',style.strokeLinecap);copy.setAttribute('stroke-linejoin',style.strokeLinejoin);
      copy.removeAttribute('class');
      if (style.transform.startsWith('matrix(-1,')) {
        const flip=node('g',{transform:`translate(${2*x+r.width} 0) scale(-1 1)`});flip.append(copy);parent.append(flip);
      } else parent.append(copy);
      return;
    }
    const group=node('g',{'data-layer':element.id || element.className || element.tagName.toLowerCase()});parent.append(group);
    if (style.backgroundColor!=='rgba(0, 0, 0, 0)') group.append(node('rect',{x,y,width:r.width,height:r.height,rx:parseFloat(style.borderTopLeftRadius)||0,fill:style.backgroundColor}));
    const uniformBorder=['Top','Bottom','Left','Right'].every(side => style[`border${side}Width`]===style.borderTopWidth && style[`border${side}Color`]===style.borderTopColor);
    if (uniformBorder && parseFloat(style.borderTopWidth)) group.append(node('rect',{x,y,width:r.width,height:r.height,rx:parseFloat(style.borderTopLeftRadius)||0,fill:'none',stroke:style.borderTopColor,'stroke-width':style.borderTopWidth}));
    for (const side of uniformBorder ? [] : ['Top','Bottom','Left','Right']) {
      const width=parseFloat(style[`border${side}Width`]);
      if (!width) continue;
      const color=style[`border${side}Color`];
      if (side==='Top') group.append(node('path',{d:`M${x} ${y}h${r.width}`,stroke:color,'stroke-width':width}));
      if (side==='Bottom') group.append(node('path',{d:`M${x} ${y+r.height}h${r.width}`,stroke:color,'stroke-width':width}));
    }
    for (const name of ['::before','::after']) {
      const pseudo=getComputedStyle(element,name);
      if (pseudo.content==='none' || pseudo.display==='none' || pseudo.backgroundColor==='rgba(0, 0, 0, 0)') continue;
      const left=parseFloat(pseudo.left), top=parseFloat(pseudo.top);
      const width=parseFloat(pseudo.width), height=parseFloat(pseudo.height);
      if (!Number.isFinite(width) || !Number.isFinite(height)) continue;
      const transform=pseudo.transform==='none'?new DOMMatrix():new DOMMatrix(pseudo.transform);
      group.append(node('rect',{x:x+(Number.isFinite(left)?left:parseFloat(style.paddingLeft))+transform.e,y:y+(Number.isFinite(top)?top:parseFloat(style.paddingTop))+transform.f,width,height,rx:parseFloat(pseudo.borderTopLeftRadius)||0,fill:pseudo.backgroundColor,stroke:pseudo.borderTopColor,'stroke-width':pseudo.borderTopWidth}));
    }
    if (['auto','hidden','scroll'].includes(style.overflowY) || element===root) {
      const id='clip'+serial++;
      const clip=node('clipPath',{id});clip.append(node('rect',{x,y,width:r.width,height:r.height,rx:element===root?32:0}));defs.append(clip);group.setAttribute('clip-path',`url(#${id})`);
    }
    if (element.tagName==='TEXTAREA' || element.tagName==='INPUT') {
      const value=element.value || element.placeholder;
      if(value) {const label=node('text',{x:x+parseFloat(style.paddingLeft),y:y+parseFloat(style.paddingTop)+parseFloat(style.fontSize),fill:element.value?style.color:'rgb(110,110,115)','font-family':style.fontFamily,'font-size':style.fontSize});label.textContent=value;group.append(label);}
    } else {
      for(const child of element.childNodes) {
        if(child.nodeType===Node.ELEMENT_NODE) visit(child,group);
        if(child.nodeType===Node.TEXT_NODE && child.textContent.trim()) text(group,child,style);
      }
    }
  }
  visit(root,svg);
  return new XMLSerializer().serializeToString(svg);
}"""


def export():
    evidence = []
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width":1440,"height":1100},device_scale_factor=3)
        for theme in ["light", "dark"]:
            folder = EXPORT / theme
            folder.mkdir(parents=True,exist_ok=True)
            for screen in ["02_chats", "03_chat", "24_settings"]:
                page.goto("about:blank")
                page.goto((ROOT/"prototype/index.html").as_uri()+f"#screen={screen}&theme={theme}")
                # Fractional page positioning otherwise adds pixels at capture edges.
                page.add_style_tag(content='.device { position:fixed !important; left:0 !important; top:0 !important; }')
                device = page.locator('.device')
                png_path = folder/f"{screen}.png"
                svg_path = folder/f"{screen}.svg"
                device.screenshot(path=str(png_path))
                svg_path.write_text(device.evaluate(SVG_EXPORT))
                dimensions = struct.unpack('>II', png_path.read_bytes()[16:24])
                assert dimensions == (1179,2556), (png_path, dimensions)
                tree = ET.parse(svg_path)
                texts = tree.findall('.//{http://www.w3.org/2000/svg}text')
                assert len(texts)>10 and not tree.findall('.//{http://www.w3.org/2000/svg}image')
                evidence.append(dict(screen=screen,theme=theme,png_dimensions=dimensions,editable_text_nodes=len(texts),raster_images_in_svg=0,status='PASS'))
        browser.close()
    (ROOT/'qa/exports.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n')
    print('Exported 6 editable SVG and 6 PNG at 3×. Typography and Figma import remain unapproved.')


if __name__ == '__main__':
    export()
