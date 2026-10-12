"""Check exported runtime names and compile/link their Swift declarations."""
import pathlib
import re
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
path = 'Telegram/SiriIntents/IntentHandler.swift'
current = (root / path).read_text(encoding='utf-8')
old = subprocess.check_output(['git', 'show', '9bb708515f:' + path], cwd=root).decode()

def names(source):
    pairs = re.findall(r'@objc\((\w+)\)\s*class (\w+)\s*:', source)
    assert ('IntentHandler', 'IntentHandler') in pairs, 'Extension principal name must remain stable'
    return pairs

def unique_names(source):
    pairs = names(source)
    exported = [objc for objc, _ in pairs]
    if len(exported) != len(set(exported)):
        raise ValueError('Duplicate Objective-C runtime class names')

def declarations(source):
    pairs = names(source)
    return 'import Foundation\n' + '\n'.join('@objc(' + objc + ') class ' + swift + ': NSObject {}' for objc, swift in pairs)

try:
    unique_names(old)
except ValueError:
    pass
else:
    raise AssertionError('Original runtime name collision was not reproduced')
unique_names(current)
# Swift's typecheck permits these aliases; do not manufacture a compiler failure
# for the old code. Their runtime-name uniqueness is a separate required check.
with tempfile.TemporaryDirectory() as directory:
    path = pathlib.Path(directory) / 'Classes.swift'
    path.write_text(declarations(current), encoding='utf-8')
    subprocess.run(['swiftc', '-emit-library', str(path), '-o', str(path.parent / 'Classes.dylib')], check=True)
    print('Original runtime-name collision detected; current exported declarations compile and link')
