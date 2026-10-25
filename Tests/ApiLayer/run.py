"""Check that the generated Api schema still declares every constructor of our layer-230 schema.

Since official 13.1 the Api types are generated from submodules/TelegramApi/swift_scheme.tl at build time (there are
no checked-in Api*.swift files), so coverage is checked by constructor name against that schema. Constructors a later
layer changed keep their name but not their id, so ids are not compared. The generated codecs have their own suite in
submodules/TelegramApi/Tests.
"""
import pathlib, re
root = pathlib.Path(__file__).resolve().parents[2]
generated = (root / 'submodules/TelegramApi/swift_scheme.tl').read_text(encoding='utf-8')
names = set(re.findall(r'^([\w.]+)#[0-9a-f]+', generated, re.M))
for line in (root / 'build-system/SwiftTL/api-230.tl').read_text(encoding='utf-8').splitlines():
    match = re.match(r'([\w.]+)#([0-9a-f]+)\b', line)
    if not match or '{X:Type}' in line or match[1] in {'true', 'error', 'null', 'vector'}:
        continue
    assert match[1] in names, 'Missing schema declaration: ' + match[1]
print('Api schema coverage passed')
