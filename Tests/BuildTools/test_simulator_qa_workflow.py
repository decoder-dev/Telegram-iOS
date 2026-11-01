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
        self.assertIn('--ui-test', WORKFLOW)
        self.assertIn('welcome-light.png', WORKFLOW)
        self.assertIn('welcome-dark.png', WORKFLOW)
        self.assertIn('recordVideo', WORKFLOW)
        self.assertIn('retention-days: 14', WORKFLOW)


if __name__ == '__main__':
    unittest.main()
