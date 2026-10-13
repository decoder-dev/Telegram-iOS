import pathlib
import re
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


class JxlServiceWorkerUid(unittest.TestCase):
    def test_production_uid_uses_webcrypto_and_returns_unique_hex(self):
        source = (ROOT / 'third-party/libjxl/libjxl/tools/wasm_demo/service_worker.js').read_text(encoding='utf-8')
        match = re.search(r'  const makeUid = \(\) => \{.*?\n  \};', source, re.S)
        self.assertIsNotNone(match)
        function = match.group(0)
        self.assertIn('self.crypto.getRandomValues(words)', function)
        self.assertNotIn('Math.random', function)

        node = shutil.which('node')
        if node is None:
            self.skipTest('Node.js is unavailable; CI executes this fixture after setup-node')

        script = """
const self = {crypto: require('node:crypto').webcrypto};
%s
const first = makeUid();
const second = makeUid();
if (!/^[0-9a-f]{32}$/.test(first) || first === second) process.exit(1);
""" % function
        result = subprocess.run([node, '-e', script], capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
