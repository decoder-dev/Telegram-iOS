import ast
import os
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class SigningTemporaryFileTests(unittest.TestCase):
    def test_key_is_private_and_deleted_after_clone_failure(self):
        # Compile the real class without importing the unrelated macOS tooling.
        tree = ast.parse((ROOT / 'build-system/Make/BuildConfiguration.py').read_text())
        definition = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'GitCodesigningSource')
        observed = []
        def clone(**kwargs):
            path = pathlib.Path(kwargs['temp_key_path'])
            observed.append(path)
            self.assertEqual(path.read_text(), 'test-only-private-key\n')
            if os.name != 'nt':
                self.assertEqual(path.stat().st_mode & 0o077, 0)
            raise RuntimeError('simulated clone failure')
        namespace = dict(os=os, tempfile=tempfile, CodesigningSource=object, load_codesigning_data_from_git=clone)
        exec(compile(ast.Module(body=[definition], type_ignores=[]), 'BuildConfiguration.py', 'exec'), namespace)
        source = namespace['GitCodesigningSource']('unused', 'test-only-private-key', 'team', 'bundle', 'adhoc', '', False)
        with self.assertRaisesRegex(RuntimeError, 'simulated clone failure'):
            source.load_data('unused')
        self.assertEqual(len(observed), 1)
        self.assertFalse(observed[0].exists())

if __name__ == '__main__':
    unittest.main()
