"""Compile the actual Foundation helpers against the real text-attribute types."""
import pathlib
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[2]


def declaration(source, name):
    start = source.index('public ' + name)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def main():
    attributes = (ROOT / 'submodules/TextFormat/Sources/ChatTextInputAttributes.swift').read_text()
    definitions = 'import Foundation\n' + '\n'.join(
        declaration(attributes, name) for name in (
            'struct ChatTextInputAttributes',
            'final class ChatTextInputTextUrlAttribute',
            'final class ChatTextInputTextQuoteAttribute',
        )
    )
    with tempfile.TemporaryDirectory(prefix='telegram-fork-refinements-') as directory:
        directory = pathlib.Path(directory)
        (directory / 'Attributes.swift').write_text(definitions)
        for name in ('ForkTrackingURL.swift', 'ForkTrackingLinks.swift'):
            source = (ROOT / 'submodules/TelegramUI/Sources' / name).read_text()
            (directory / name).write_text(source.replace('import TextFormat\n', ''))
        (directory / 'main.swift').write_text((ROOT / 'Tests/ForkRefinements/tracking_links.swift').read_text())
        executable = directory / 'tracking-links'
        subprocess.run(['swiftc', '-o', str(executable), *(str(path) for path in directory.glob('*.swift'))], check=True)
        subprocess.run([str(executable)], check=True, timeout=20)


if __name__ == '__main__':
    main()
