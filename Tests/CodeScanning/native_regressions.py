"""Run the existing codec round-trip suites on an Apple Silicon host."""
import pathlib
import re
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'third-party' / 'subcodec'


def run(*command):
    subprocess.run(command, check=True, cwd=ROOT)


def main():
    cmake = (SOURCE / 'CMakeLists.txt').read_text()
    targets = []
    for name in ('CORE_TESTS', 'E2E_TESTS'):
        match = re.search(r'set\(' + name + r'\s+([^)]*)\)', cmake)
        if match is None:
            raise RuntimeError('Missing codec test target list: ' + name)
        targets.extend(match.group(1).split())
    if not targets or len(targets) != len(set(targets)):
        raise RuntimeError('The codec test target list must be nonempty and unique')
    with tempfile.TemporaryDirectory(prefix='telegram-codec-regressions-') as directory:
        run('cmake', '-S', str(SOURCE), '-B', directory, '-DCMAKE_BUILD_TYPE=Release')
        run('cmake', '--build', directory, '--parallel', '3', '--target', *targets)
        # Several existing tests use fixed /tmp fixture names; keep execution serial.
        run('ctest', '--test-dir', directory, '--output-on-failure', '--parallel', '1')


if __name__ == '__main__':
    main()
