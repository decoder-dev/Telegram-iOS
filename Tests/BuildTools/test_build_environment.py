import contextlib
import importlib.util
import io
import pathlib
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    'build_environment', ROOT / 'build-system/Make/BuildEnvironment.py'
)
BUILD_ENVIRONMENT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILD_ENVIRONMENT)


class BuildEnvironmentLogging(unittest.TestCase):
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


if __name__ == '__main__':
    unittest.main()
