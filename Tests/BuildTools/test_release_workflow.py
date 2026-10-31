import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
WORKFLOW = (ROOT / '.github/workflows/build.yml').read_text(encoding='utf-8')


def job(name):
    """The text of one job of build.yml, up to the next job."""
    start = WORKFLOW.index('\n  ' + name + ':\n')
    rest = WORKFLOW[start + 1:]
    following = [rest.index('\n  ' + other + ':\n') for other in ('regression', 'build', 'publish') if other != name and ('\n  ' + other + ':\n') in rest]
    return rest[:min(following)] if following else rest


class ReleaseWorkflow(unittest.TestCase):
    """31 Oct audit, C-8: the job that builds third-party code (submodules, downloaded archives) must not be able to
    write releases, a release is published only for a commit on main, and it carries its checksum."""

    def test_only_publish_writes(self):
        self.assertIn('\npermissions:\n  contents: read\n', WORKFLOW)
        settings = [line.strip() for line in WORKFLOW.splitlines() if not line.lstrip().startswith('#')]
        self.assertEqual(settings.count('contents: write'), 1)
        self.assertIn('contents: write', job('publish'))
        self.assertIn('contents: read', job('build'))
        self.assertNotIn('gh release', job('build'))

    def test_publish_requires_main_and_ships_checksums(self):
        publish = job('publish')
        self.assertIn('needs: build', publish)
        self.assertIn('git merge-base --is-ancestor "$GITHUB_SHA" origin/main', publish)
        self.assertIn('sha256sum "$IPA_NAME" > SHA256SUMS.txt', publish)
        self.assertIn('gh release upload "$TAG" "$IPA" "$SUMS" --clobber', publish)
        self.assertEqual(publish.count('gh release create "$TAG" "$IPA" "$SUMS"'), 2)
        self.assertNotIn('submodules: recursive', publish)

    def test_stable_release_never_skips_regression(self):
        self.assertIn('if: ${{ !inputs.skip_regression || inputs.stable_release }}', job('regression'))


if __name__ == '__main__':
    unittest.main()
