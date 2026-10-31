"""Keep Spotlight avatar resolution off the shared Postbox transaction queue."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class SpotlightTransactionTests(unittest.TestCase):
    def test_only_privacy_snapshot_runs_in_the_transaction(self):
        source = (ROOT / 'submodules/TelegramUI/Sources/SpotlightContacts.swift').read_text()
        start = source.index('return account.postbox.transaction', source.index('private func manageableSpotlightContacts'))
        end = source.index('|> deliverOn(queue)', start)
        transaction = source[start:end]
        self.assertIn('return archiveLockedPeerIds(transaction: transaction)', transaction)
        self.assertNotIn('resourcePath(', transaction)
        self.assertNotIn('for peer in peers', transaction)
        mapping = source[end:source.index('|> distinctUntilChanged', end)]
        self.assertIn('map { locked ->', mapping)
        self.assertIn('if locked.contains(peer.id)', mapping)
        self.assertIn('engine.resources.resourcePath(', mapping)


if __name__ == '__main__':
    unittest.main()
