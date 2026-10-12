import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('release_notes', ROOT / 'build-system/Make/LimitReleaseNotes.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReleaseNotes(unittest.TestCase):
    def test_small_changelog_unchanged(self):
        text = '- Fix screenshots 🍌\n- Fix ghost reads\n'
        self.assertEqual(module.bounded_changelog(text, 'decoder-dev/Telegram-iOS', 'abcdef'), text)

    def test_large_official_history_fits_and_links_to_full_history(self):
        text = '- Исправление 🍌 (1234567)\n' * 20000
        result = module.bounded_changelog(text, 'decoder-dev/Telegram-iOS', 'abcdef')
        self.assertLessEqual(len(result.encode('utf-8')), module.MAX_CHANGELOG_BYTES)
        self.assertLess(len(result), 125000)
        self.assertIn('https://github.com/decoder-dev/Telegram-iOS/commits/abcdef', result)
        self.assertNotIn('\ufffd', result)
        self.assertTrue(result.startswith('- Исправление 🍌 (1234567)\n'))

    def test_workflow_bounds_only_changelog_before_notes(self):
        workflow = (ROOT / '.github/workflows/build.yml').read_text(encoding='utf-8')
        step = workflow.split('- name: Publish GitHub release', 1)[1]
        self.assertLess(step.index('LimitReleaseNotes.py "$CHANGELOG_BODY"'), step.index('cat > "$NOTES"'))
        self.assertIn('--notes-file "$NOTES"', step)
        self.assertIn('--prerelease --latest=false', step)


if __name__ == '__main__':
    unittest.main()
