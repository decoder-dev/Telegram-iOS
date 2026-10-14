"""Exercise the real Bazel installer with local files and simulated downloads."""
import hashlib
import importlib.util
import pathlib
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[2]
with mock.patch.dict(sys.modules, BuildEnvironment=SimpleNamespace(
        is_apple_silicon=lambda: True, resolve_executable=None, call_executable=None,
        run_executable_with_status=None, BuildEnvironmentVersions=None)):
    spec = importlib.util.spec_from_file_location('bazel_location_under_test', ROOT / 'build-system/Make/BazelLocation.py')
    BAZEL = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(BAZEL)


class BazelDownloadTests(unittest.TestCase):
    payload = b'valid-bazel-test-fixture'

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.digest = hashlib.sha256(self.payload).hexdigest()
        self.target = self.root / 'build-input/bazel-test-darwin-arm64'
        self.versions = SimpleNamespace(bazel_version='test', bazel_version_sha256=self.digest)
        self.version_loader = mock.Mock(return_value=self.versions)
        patcher = mock.patch.object(BAZEL, 'BuildEnvironmentVersions', self.version_loader)
        patcher.start()
        self.addCleanup(patcher.stop)

    def download(self, data):
        def call(arguments, **kwargs):
            if '--output' in arguments:
                destination = pathlib.Path(arguments[arguments.index('--output') + 1])
                # A partial transfer must never be visible at the executable's path.
                self.assertNotEqual(destination, self.target)
                self.assertFalse(self.target.exists())
                destination.write_bytes(data)
        return call

    def assert_no_staging_files(self):
        self.assertEqual(list((self.root / 'build-input').iterdir()), [])

    def test_good_download_is_verified_before_installation(self):
        with mock.patch.object(BAZEL, 'call_executable', side_effect=self.download(self.payload)) as call:
            result = BAZEL.locate_bazel(str(self.root), None, None)
        self.assertEqual(pathlib.Path(result).read_bytes(), self.payload)
        self.version_loader.assert_called_once_with(base_path=str(self.root))
        arguments = call.call_args.args[0]
        self.assertIn('--fail', arguments)
        self.assertIn('--proto-redir', arguments)

    def test_bad_download_is_rejected_without_cache_upload_or_installation(self):
        with mock.patch.object(BAZEL, 'call_executable', side_effect=self.download(b'corrupted')) as call:
            with self.assertRaisesRegex(RuntimeError, 'SHA256'):
                BAZEL.locate_bazel(str(self.root), 'grpc://cache.example', None)
        self.assertFalse(any('PUT' in invocation.args[0] for invocation in call.call_args_list))
        self.assert_no_staging_files()

    def test_failed_transfer_cleans_partial_file(self):
        def fail(arguments, **kwargs):
            self.download(b'partial')(arguments, **kwargs)
            raise RuntimeError('download failed')
        with mock.patch.object(BAZEL, 'call_executable', side_effect=fail):
            with self.assertRaisesRegex(RuntimeError, 'download failed'):
                BAZEL.locate_bazel(str(self.root), None, None)
        self.assert_no_staging_files()

    def test_corrupt_local_cache_falls_back_to_verified_download(self):
        cache = self.root / 'cache'
        entry = cache / 'cas' / self.digest[:2] / self.digest
        entry.parent.mkdir(parents=True)
        entry.write_bytes(b'corrupt-cache')
        with mock.patch.object(BAZEL, 'call_executable', side_effect=self.download(self.payload)):
            BAZEL.locate_bazel(str(self.root), None, str(cache))
        self.assertEqual(self.target.read_bytes(), self.payload)
        self.assertEqual(entry.read_bytes(), self.payload)

    def test_valid_existing_binary_does_not_need_network(self):
        self.target.parent.mkdir()
        self.target.write_bytes(self.payload)
        with mock.patch.object(BAZEL, 'call_executable') as call:
            BAZEL.locate_bazel(str(self.root), None, None)
        call.assert_not_called()

    def test_corrupt_existing_binary_is_replaced_only_after_verification(self):
        self.target.parent.mkdir()
        self.target.write_bytes(b'old-corrupted-binary')
        with mock.patch.object(BAZEL, 'call_executable', side_effect=self.download(self.payload)):
            BAZEL.locate_bazel(str(self.root), None, None)
        self.assertEqual(self.target.read_bytes(), self.payload)

    def test_valid_remote_cache_avoids_release_download_and_upload(self):
        with mock.patch.object(BAZEL, 'call_executable', side_effect=self.download(self.payload)) as call:
            BAZEL.locate_bazel(str(self.root), 'grpc://cache.example', None)
        self.assertEqual(call.call_count, 1)
        self.assertEqual(self.target.read_bytes(), self.payload)

    def test_valid_local_cache_needs_no_network(self):
        entry = self.root / 'cache/cas' / self.digest[:2] / self.digest
        entry.parent.mkdir(parents=True)
        entry.write_bytes(self.payload)
        with mock.patch.object(BAZEL, 'call_executable') as call:
            BAZEL.locate_bazel(str(self.root), None, str(self.root / 'cache'))
        call.assert_not_called()
        self.assertEqual(self.target.read_bytes(), self.payload)

    def test_missing_or_malformed_digest_fails_before_network(self):
        for digest in [None, '', 'not-a-sha256', '../outside']:
            with self.subTest(digest=digest):
                self.versions.bazel_version_sha256 = digest
                with mock.patch.object(BAZEL, 'call_executable') as call:
                    with self.assertRaisesRegex(ValueError, 'SHA256'):
                        BAZEL.locate_bazel(str(self.root), None, None)
                call.assert_not_called()


if __name__ == '__main__':
    unittest.main()
