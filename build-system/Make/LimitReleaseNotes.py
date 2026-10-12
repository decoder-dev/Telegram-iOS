"""Bound the changelog before inserting it into the GitHub release description."""
import pathlib
import sys

MAX_CHANGELOG_BYTES = 90000


def bounded_changelog(text, repository, commit):
    if len(text.encode('utf-8')) <= MAX_CHANGELOG_BYTES:
        return text
    suffix = ('\n\n_Commit list abbreviated to fit GitHub release limits. '
              'Full history: https://github.com/' + repository + '/commits/' + commit + '_\n')
    budget = MAX_CHANGELOG_BYTES - len(suffix.encode('utf-8'))
    prefix = text.encode('utf-8')[:budget].decode('utf-8', errors='ignore')
    # Avoid splitting a Markdown commit row (and a Unicode code point).
    prefix = prefix.rsplit('\n', 1)[0] if '\n' in prefix else prefix
    return prefix + suffix


if __name__ == '__main__':
    path = pathlib.Path(sys.argv[1])
    path.write_text(bounded_changelog(path.read_text(encoding='utf-8'), sys.argv[2], sys.argv[3]), encoding='utf-8')
