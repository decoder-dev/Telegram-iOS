"""Compile the production Punycode codec and check malformed input and RFC round trips."""
import json
import pathlib
import random
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
values = ['bücher', 'пример', '例子', 'mañana', '日本語', '☃', '😀', 'e\u0301', 'ABC', 'a-b', '\r\n', 'a\r\nb', '\r\né', 'abc\r\n😀']
generator = random.Random(3492)
alphabet = list('abc-') + ['é', 'я', '中', '😀', '\u0301']
values += [''.join(generator.choice(alphabet) for _ in range(generator.randint(1, 20))) for _ in range(200)]
fixtures = [[text, text.encode('punycode').decode('ascii')] for text in values]
for pair in fixtures:
    pair.append(pair[1].upper().encode('ascii').decode('punycode'))
checks = r'''
let codec = Punycode()
precondition(codec.decodePunycode(Substring(String(repeating: "9", count: 100))) == nil)
precondition(codec.decodedIDNA(Substring("xn--" + String(repeating: "9", count: 100) + ".example")) == nil)
precondition(codec.decodedIDNA("xn--bcher-kva.example") == "bücher.example")
for invalid in ["z", "9", "é-", "a\u{301}"] {
    precondition(codec.decodePunycode(Substring(invalid)) == nil, invalid)
}
for pair in fixtures {
    let plain = pair[0], encoded = pair[1]
    precondition(codec.encodePunycode(Substring(plain)) == encoded, plain)
    precondition(codec.decodePunycode(Substring(encoded)) == plain, encoded)
    precondition(codec.decodePunycode(Substring(encoded.uppercased())) == pair[2], encoded)
}
print("Punycode overflow, truncated/non-ASCII input and \(fixtures.count) reference round trips passed")
'''
with tempfile.TemporaryDirectory(prefix='telegram-url-codec-') as directory:
    path = pathlib.Path(directory)
    source = (ROOT / 'submodules/UrlEscaping/Sources/Punycode.swift').read_text()
    source += '\nlet fixtures = try JSONDecoder().decode([[String]].self, from: Data(#"' + json.dumps(fixtures, ensure_ascii=False) + '"#.utf8))\n'
    (path / 'main.swift').write_text(source + checks)
    subprocess.run(['swiftc', '-O', '-warnings-as-errors', str(path / 'main.swift'), '-o', str(path / 'checks')], check=True, timeout=120)
    subprocess.run([str(path / 'checks')], check=True, timeout=30)
