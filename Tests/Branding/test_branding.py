import json
import pathlib
import plistlib
import re
import struct
import unittest
import zlib
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
