"""Execute production command construction without macOS-only imports."""
import ast
import contextlib
import io
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

    def test_verbose_cli_does_not_dump_credentials(self):
        tree = ast.parse((ROOT / 'build-system/Make/Make.py').read_text(encoding='utf-8'))
        verbose = next(node for node in ast.walk(tree)
                       if isinstance(node, ast.If) and isinstance(node.test, ast.Attribute)
                       and isinstance(node.test.value, ast.Name) and node.test.value.id == 'args'
                       and node.test.attr == 'verbose')
        arguments = SimpleNamespace(verbose=True, commandName='build', watchApiHash='private-api-sentinel',
                                    cacheHost='https://user:private-cache-sentinel@cache.example')
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            exec(compile(ast.Module(body=[verbose], type_ignores=[]), 'Make.py', 'exec'), dict(args=arguments))
        self.assertIn('build', output.getvalue())
        self.assertNotIn('private-api-sentinel', output.getvalue())
        self.assertNotIn('private-cache-sentinel', output.getvalue())

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
                common_args=[], common_build_args=['--define=watchApiHash=api-hash-sentinel'], build_number=1,
                embed_watch_app=False, split_submodules=False, remote_cache='https://user:cache-token-sentinel@cache.example',
                cache_dir=None, profile_swift=False, configuration_args=[],
                compile_extensions=enabled).items():
                setattr(command, name, value)
            command.build_environment = SimpleNamespace(bazel_path='test-bazel')
            calls = []
            command.invoke_build.__globals__['call_executable'] = calls.append
            command.invoke_build.__globals__['subprocess'] = subprocess
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                command.invoke_build()
            self.assertNotIn('api-hash-sentinel', output.getvalue())
            self.assertNotIn('cache-token-sentinel', output.getvalue())
            self.assertEqual(len(calls), 1)
            args = calls[0]
            self.assertIn('--define=watchApiHash=api-hash-sentinel', args)
            self.assertIn('--remote_cache=https://user:cache-token-sentinel@cache.example', args)
            self.assertIn('Telegram/Telegram', args)
            self.assertIn('--//Telegram:disableExtensions', args)
            self.assertEqual('//Telegram:ExtensionLibrariesBuildCheck' in args, enabled)
            for target in ['//Telegram:ShareExtensionLib', '//Telegram:NotificationContentExtensionLib',
                           '//Telegram:WidgetExtensionLib', '//Telegram:IntentsExtensionLib',
                           '//Telegram/NotificationService:NotificationServiceExtensionLib']:
                self.assertNotIn(target, args, target)

    def test_extension_check_applies_ios_transition_to_all_libraries(self):
        source = (ROOT / 'Telegram/BUILD').read_text(encoding='utf-8')
        start = source.index('ios_build_test(\n    name = "ExtensionLibrariesBuildCheck"')
        block = source[start:source.index('\n)', start)]
        self.assertIn('minimum_os_version = minimum_os_version', block)
        for target in [':ShareExtensionLib', ':NotificationContentExtensionLib',
                       ':WidgetExtensionLib', ':IntentsExtensionLib',
                       '//Telegram/NotificationService:NotificationServiceExtensionLib']:
            self.assertIn('"' + target + '"', block)

    def test_share_warning_policy_does_not_require_xcode27_groups(self):
        source = (ROOT / 'Telegram/BUILD').read_text(encoding='utf-8')
        start = source.index('name = "ShareExtensionLib"')
        block = source[start:source.index('\n)', start)]
        self.assertIn('"-warnings-as-errors"', block)
        self.assertNotIn('"-Wwarning"', block)
        workflow = (ROOT / '.github/workflows/build.yml').read_text(encoding='utf-8')
        adaptation = workflow.split('- name: Adapt sources to the Xcode 27 SDK', 1)[1].split('- name:', 1)[0]
        self.assertIn("inputs.toolchain == 'xcode27'", adaptation)
        self.assertIn('ImplicitStrongCapture', adaptation)

if __name__ == '__main__':
    unittest.main()
