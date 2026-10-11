"""Parse all changed production Swift files before the expensive IPA compilation."""
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
files = subprocess.check_output(['git', 'diff', '--name-only', '6fd195d294be0a6f5a831b2de5671250faaecbe8', '--', '*.swift'], cwd=ROOT).decode().splitlines()
files = [f for f in files if f.startswith(('Telegram/', 'submodules/')) and (ROOT / f).is_file()]
for offset in range(0, len(files), 40):
    subprocess.run(['swiftc', '-frontend', '-parse', *files[offset:offset + 40]], cwd=ROOT, check=True, timeout=120)
print(f'Parsed {len(files)} changed production Swift files')
