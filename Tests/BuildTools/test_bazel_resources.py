"""Execute production command construction without macOS-only imports."""
import ast
import os
import pathlib
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[2]

class BazelResourcesTests(unittest.TestCase):
    def command(self, fast):
        source = (ROOT / 'build-system/Make/Make.py').read_text(encoding='utf-8')
        tree = ast.parse(source)
        definition = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'BazelCommandLine')
        namespace = dict(os=os)
        exec(compile(ast.Module(body=[definition], type_ignores=[]), 'Make.py', 'exec'), namespace)
        command = object.__new__(namespace['BazelCommandLine'])
        command.ci_fast = fast
        command.skip_dsym = True
        command.common_debug_args = ['--debug-sentinel']
        command.common_release_args = ['--release-sentinel']
        return command

    def test_all_fast_configurations_use_bazel9_resource_option(self):
        for config in ['debug_arm64', 'debug_sim_arm64', 'release_sim_arm64', 'ci_arm64', 'release_arm64']:
            with self.subTest(config=config), patch.object(os, 'cpu_count', return_value=3):
                command = self.command(True)
                command.set_configuration(config)
                self.assertIn('--jobs=3', command.configuration_args)
                self.assertIn('--local_resources=cpu=3', command.configuration_args)
                self.assertFalse(any(a.startswith('--local_cpu_resources') for a in command.configuration_args))

    def test_normal_release_keeps_optimizations(self):
        command = self.command(False)
        command.set_configuration('release_arm64')
        self.assertIn('--release-sentinel', command.configuration_args)
        self.assertNotIn('--local_resources=cpu=3', command.configuration_args)

    def test_repo_cache_is_outside_checkout(self):
        workflow = (ROOT / '.github/workflows/build.yml').read_text(encoding='utf-8')
        self.assertIn('BAZEL_REPO_CACHE: /private/var/tmp/telegram-bazel-repo-cache', workflow)
        self.assertNotIn('BAZEL_REPO_CACHE: ${{ github.workspace }}', workflow)

if __name__ == '__main__':
    unittest.main()
