import ast
import json
import pathlib
import plistlib
import re
import struct
import unittest
import zlib
import xml.etree.ElementTree as ET
ROOT = pathlib.Path(__file__).resolve().parents[2]

class BrandingTests(unittest.TestCase):
    def test_png_assets(self):
        manifest = json.loads((ROOT/'assets/branding/manifest.json').read_text())
        self.assertGreater(len(manifest), 150)
        for asset in manifest:
            with self.subTest(file=asset['file']):
                data = (ROOT/asset['file']).read_bytes()
                self.assertEqual(data[:8], b'\x89PNG\r\n\x1a\n')
                w,h,depth,color = struct.unpack('>IIBB',data[16:26])
                self.assertEqual([w,h],asset['size'])
                self.assertEqual(color,2, 'App icons must be opaque RGB')
                offset=8
                while offset<len(data):
                    size=struct.unpack('>I',data[offset:offset+4])[0]
                    chunk=data[offset+4:offset+8+size]
                    crc=struct.unpack('>I',data[offset+8+size:offset+12+size])[0]
                    self.assertEqual(zlib.crc32(chunk),crc)
                    offset+=12+size
    def test_icon_mark_contrast_in_every_palette(self):
        # Read the actual generator palette without importing its optional rendering libraries.
        tree = ast.parse((ROOT/'tools/branding/generate_icons.py').read_text(encoding='utf-8'))
        constants = {}
        def value(node):
            if isinstance(node, ast.Name):
                return constants[node.id]
            if isinstance(node, ast.Constant):
                return node.value
            if isinstance(node, ast.Tuple):
                return tuple(value(item) for item in node.elts)
            if isinstance(node, ast.Dict):
                return {value(key): value(item) for key,item in zip(node.keys,node.values)}
            raise ValueError(type(node).__name__)
        for statement in tree.body:
            if isinstance(statement, ast.Assign) and len(statement.targets)==1 and isinstance(statement.targets[0],ast.Name):
                name=statement.targets[0].id
                if name in ('YELLOW','GOLD','INK','WHITE_PLANE','PALETTES'):
                    constants[name]=value(statement.value)
        def channels(hex_color):
            return tuple(int(hex_color[i:i+2],16) for i in (1,3,5))
        def luminance(rgb):
            linear=[v/255/12.92 if v/255<=.04045 else ((v/255+.055)/1.055)**2.4 for v in rgb]
            return sum(v*w for v,w in zip(linear,(.2126,.7152,.0722)))
        for name,(_,top,bottom,glow,peel,plane) in constants['PALETTES'].items():
            for step in range(101):
                background=tuple(a*(1-step/100)+b*step/100 for a,b in zip(channels(top),channels(bottom)))
                for light in (0,.16):
                    lit=tuple(a*(1-light)+b*light for a,b in zip(background,channels(glow)))
                    for mark in (*peel,plane[0]):
                        low,high=sorted((luminance(channels(mark)),luminance(lit)))
                        self.assertGreaterEqual((high+.05)/(low+.05),3.0,(name,step,light,mark))

    def test_composer_layers_are_present_and_keep_their_opacity(self):
        folder = ROOT/'Telegram/Telegram-iOS/Telegram.icon'
        config = json.loads((folder/'icon.json').read_text())
        names = []
        for group in config['groups']:
            self.assertFalse(group['translucency']['enabled'], 'Translucency washes out the mark on light backgrounds')
            for layer in group['layers']:
                names.append(layer['image-name'])
                document = ET.parse(folder/'Assets'/layer['image-name']).getroot()
                self.assertEqual(document.attrib['viewBox'],'0 0 1024 1024')
                self.assertTrue(document.findall('.//{http://www.w3.org/2000/svg}path'))
                self.assertFalse(document.findall('.//{http://www.w3.org/2000/svg}rect'), 'Only the system supplies the layer background')
        self.assertEqual(set(names),{'Banana.svg','PaperPlane.svg'})

    def test_catalog_sizes(self):
        for catalog in (ROOT/'Telegram').rglob('*.appiconset/Contents.json'):
            if 'Watch' not in str(catalog) and 'Telegram-iOS' not in str(catalog): continue
            for item in json.loads(catalog.read_text()).get('images',[]):
                if 'filename' not in item: continue
                path=catalog.parent/item['filename']
                self.assertTrue(path.exists(), str(path))
                w,h=struct.unpack('>II',path.read_bytes()[16:24])
                scale=float(item.get('scale','1x').rstrip('x'))
                expected=[round(float(v)*scale) for v in item['size'].split('x')]
                self.assertEqual([w,h],expected,str(path))
    def test_app_name(self):
        for name in ['Info.plist','InfoBazel.plist']:
            data=plistlib.loads((ROOT/'Telegram/Telegram-iOS'/name).read_bytes())
            self.assertEqual(data['CFBundleDisplayName'],'BananaGram')
        for path in (ROOT/'Telegram/Telegram-iOS').glob('*.lproj/InfoPlist.strings'):
            data=path.read_bytes()
            text=data.decode('utf-16' if data[:2] in (b'\xff\xfe',b'\xfe\xff') else 'utf-8-sig')
            for value in re.findall(r'"CFBundleDisplayName"\s*=\s*"([^"]+)"',text):
                self.assertEqual(value,'BananaGram',str(path))
if __name__=='__main__': unittest.main()
