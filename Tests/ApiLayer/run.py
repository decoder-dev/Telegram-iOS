"""Check schema coverage and execute generated Swift wire codecs."""
import pathlib, re, subprocess, tempfile
root = pathlib.Path(__file__).resolve().parents[2]
sources = root / 'submodules/TelegramApi/Sources'
api = '\n'.join(p.read_text(encoding='utf-8') for p in sources.glob('Api*.swift'))
ids = {int(v) & 0xffffffff for v in re.findall(r'appendInt32\((-?\d+)\)', api)}
for line in (root / 'build-system/SwiftTL/api-229.tl').read_text(encoding='utf-8').splitlines():
    match = re.match(r'([\w.]+)#([0-9a-f]+)\b', line)
    if not match or '{X:Type}' in line or match[1] in {'true', 'error', 'null', 'vector'}:
        continue
    assert int(match[2], 16) in ids, 'Missing schema declaration: ' + match[1]
with tempfile.TemporaryDirectory() as temporary:
    executable = pathlib.Path(temporary) / 'api-tests'
    files = sorted(sources.glob('Api*.swift')) + [sources / name for name in ['Buffer.swift', 'DeserializeFunctionResponse.swift', 'TelegramApiLogger.swift']]
    subprocess.run(['swiftc', '-o', str(executable), *map(str, files), str(pathlib.Path(__file__).with_name('main.swift'))], check=True)
    subprocess.run([str(executable)], check=True)
