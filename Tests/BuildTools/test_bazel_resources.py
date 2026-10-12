"""Execute production command construction without macOS-only imports."""
import ast
import os
import pathlib
import unittest
import subprocess
from types import SimpleNamespace
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

    def test_extension_libraries_are_checked_without_changing_embedding(self):
        for enabled in [False, True]:
            command = self.command(False)
            for name, value in dict(bazel_user_root=None, lock=False, custom_target=None,
                continue_on_error=True, show_actions=False, enable_sandbox=False,
                disable_provisioning_profiles=False, disable_extensions=True,
                common_args=[], common_build_args=[], build_number=1,
                embed_watch_app=False, split_submodules=False, remote_cache=None,
                cache_dir=None, profile_swift=False, configuration_args=[],
                compile_extensions=enabled).items():
                setattr(command, name, value)
            command.build_environment = SimpleNamespace(bazel_path='test-bazel')
            calls = []
            command.invoke_build.__globals__['call_executable'] = calls.append
            command.invoke_build.__globals__['subprocess'] = subprocess
            command.invoke_build()
            self.assertEqual(len(calls), 1)
            args = calls[0]
            self.assertIn('Telegram/Telegram', args)
            self.assertIn('--//Telegram:disableExtensions', args)
            for target in ['//Telegram:ShareExtensionLib', '//Telegram:NotificationContentExtensionLib',
                           '//Telegram:WidgetExtensionLib', '//Telegram:IntentsExtensionLib',
                           '//Telegram/NotificationService:NotificationServiceExtensionLib']:
                self.assertEqual(target in args, enabled, target)

if __name__ == '__main__':
    unittest.main()
