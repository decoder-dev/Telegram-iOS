import contextlib
import importlib.util
import io
import pathlib
import subprocess
import traceback
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    'build_environment', ROOT / 'build-system/Make/BuildEnvironment.py'
)
BUILD_ENVIRONMENT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILD_ENVIRONMENT)


class BuildEnvironmentLogging(unittest.TestCase):
    def test_call_executable_failure_traceback_does_not_echo_credentials(self):
        credential = 'private-build-password-sentinel'
        arguments = ['tool', '--password', credential]
        failure = subprocess.CalledProcessError(23, arguments)
        with mock.patch.object(BUILD_ENVIRONMENT, 'resolve_executable', return_value='tool'), \
                mock.patch.object(BUILD_ENVIRONMENT.subprocess, 'check_call', side_effect=failure):
            try:
                BUILD_ENVIRONMENT.call_executable(arguments)
            except BaseException:
                diagnostic = traceback.format_exc()
            else:
                self.fail('A failed command must stop the caller')
        self.assertNotIn(credential, diagnostic)
        self.assertIn('23', diagnostic)

    def test_output_helper_preserves_binary_output_when_decode_is_false(self):
        process = mock.Mock()
        process.communicate.return_value = (b'\xff\x00\xfe', None)
        process.returncode = 0
        with mock.patch.object(BUILD_ENVIRONMENT, 'resolve_executable', return_value='tool'), \
                mock.patch.object(BUILD_ENVIRONMENT.subprocess, 'Popen', return_value=process):
            self.assertEqual(BUILD_ENVIRONMENT.run_executable_with_output('tool', [], decode=False), b'\xff\x00\xfe')

    def test_failed_command_does_not_echo_credentials(self):
        credential = 'appcenter-secret-token'
        output = io.StringIO()
        with mock.patch.object(BUILD_ENVIRONMENT.os, 'system', return_value=1), \
                contextlib.redirect_stdout(output), self.assertRaises(SystemExit):
            BUILD_ENVIRONMENT.check_run_system(
                'appcenter login --token {}'.format(credential)
            )

        self.assertNotIn(credential, output.getvalue())
        self.assertIn('exit status', output.getvalue())

    def test_failed_executable_does_not_echo_arguments_or_output(self):
        credential = 'keychain-password-sentinel'
        process = mock.Mock()
        process.communicate.return_value = (
            ('failure {}'.format(credential)).encode('utf-8'), None
        )
        process.returncode = 1
        output = io.StringIO()
        with mock.patch.object(BUILD_ENVIRONMENT, 'resolve_executable', return_value='tool'), \
                mock.patch.object(BUILD_ENVIRONMENT.subprocess, 'Popen', return_value=process), \
                contextlib.redirect_stdout(output), self.assertRaises(SystemExit):
            BUILD_ENVIRONMENT.run_executable_with_output(
                'tool', ['--password', credential], print_command=True, check_result=True
            )

        self.assertNotIn(credential, output.getvalue())
        self.assertIn('exit status 1', output.getvalue())


if __name__ == '__main__':
    unittest.main()
