import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
WORKFLOW = (ROOT / '.github/workflows/simulator-qa.yml').read_text(encoding='utf-8')


class SimulatorQAWorkflow(unittest.TestCase):
    def test_manual_only_and_read_only_permissions(self):
        self.assertIn('workflow_dispatch:', WORKFLOW)
        self.assertNotIn('\n  push:', WORKFLOW)
        self.assertIn('permissions:\n  contents: read', WORKFLOW)

    def test_builds_isolated_simulator_app_and_captures_evidence(self):
        self.assertIn('--configuration=debug_sim_arm64', WORKFLOW)
        self.assertIn('--disableExtensions', WORKFLOW)
        self.assertIn('shasum -a 256 -c -', WORKFLOW)
        self.assertIn('LibXray.xcframework/ios-arm64-simulator', WORKFLOW)
        self.assertIn('--ui-test', WORKFLOW)
        self.assertIn('welcome-light.png', WORKFLOW)
        self.assertIn('welcome-dark.png', WORKFLOW)
        self.assertIn('recordVideo', WORKFLOW)
        self.assertIn('retention-days: 14', WORKFLOW)

    def test_installs_the_fresh_package_and_records_its_environment(self):
        self.assertIn('unzip -q bazel-bin/Telegram/Telegram.ipa', WORKFLOW)
        self.assertIn('APP="$STAGE/Payload/Telegram.app"', WORKFLOW)
        self.assertNotIn('find -L bazel-bin', WORKFLOW)
        self.assertIn('qa-artifacts/environment.txt', WORKFLOW)
        self.assertIn('git rev-parse HEAD', WORKFLOW)

    def test_qa_and_device_build_share_toolchain_setup(self):
        build = (ROOT / '.github/workflows/build.yml').read_text(encoding='utf-8')
        for workflow in (WORKFLOW, build):
            self.assertIn('uses: ./.github/actions/prepare-apple-toolchain', workflow)
        self.assertIn('options: [xcode27, xcode26]', WORKFLOW)
        self.assertIn('bazel-warm-simulator-${{ inputs.toolchain }}-', WORKFLOW)
        # Device builds now run Simulator tests too; their runtimes must survive disk cleanup.
        self.assertNotIn('/CoreSimulator/Profiles/Runtimes/*', build)


if __name__ == '__main__':
    unittest.main()
