"""Typecheck Siri's exported class names; reproduce the original collision."""
import pathlib
import re
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
path = 'Telegram/SiriIntents/IntentHandler.swift'
current = (root / path).read_text(encoding='utf-8')
old = subprocess.check_output(['git', 'show', '9bb708515f:' + path], cwd=root).decode()

def declarations(source):
    pairs = re.findall(r'@objc\((\w+)\)\s*class (\w+)\s*:', source)
    assert ('IntentHandler', 'IntentHandler') in pairs, 'Extension principal name must remain stable'
    return 'import Foundation\n' + '\n'.join('@objc(' + objc + ') class ' + swift + ': NSObject {}' for objc, swift in pairs)

with tempfile.TemporaryDirectory() as directory:
    path = pathlib.Path(directory) / 'Classes.swift'
    path.write_text(declarations(old), encoding='utf-8')
    previous = subprocess.run(['swiftc', '-typecheck', str(path)], capture_output=True, text=True)
    assert previous.returncode != 0 and 'Objective-C name' in previous.stderr, previous.stderr
    path.write_text(declarations(current), encoding='utf-8')
    subprocess.run(['swiftc', '-typecheck', str(path)], check=True)
    print('Original Siri Objective-C class-name collision reproduced; current exported names typecheck')
