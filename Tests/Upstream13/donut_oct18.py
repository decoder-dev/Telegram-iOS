"""Donutgram Oct 18 ports: execute production parsing and retention policies on macOS."""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


def stripped(source):
    return '\n'.join(line for line in source.splitlines() if not line.startswith('import '))


def execute(source):
    with tempfile.TemporaryDirectory(prefix='banana-donut18-') as directory:
        path = Path(directory) / 'main.swift'
        path.write_text(source, encoding='utf-8')
        binary = Path(directory) / 'check'
        subprocess.run(['swiftc', '-warnings-as-errors', str(path), '-o', str(binary)], check=True, timeout=120)
        subprocess.run([str(binary)], check=True, timeout=60)


class Integration(unittest.TestCase):
    def test_retention_covers_sync_reset_pins_and_cached_profile(self):
        peers = read('submodules/TelegramCore/Sources/UpdatePeers.swift')
        self.assertLess(peers.index('bananaUpdateBannedChat('), peers.index('switch peerId.namespace'))
        for name, marker in [
            ('State/Holes.swift', 'bananaIsPreservedBannedChat(transaction: transaction, peerId: archivedPeerId)'),
            ('State/ResetState.swift', 'preservedBannedChats.append'),
            ('State/ManagedSynchronizePinnedChatsOperations.swift', 'for itemId in serverItemIds'),
            ('TelegramEngine/Peers/UpdateCachedPeerData.swift', 'if isPreservedBannedChat, let current'),
        ]:
            self.assertTrue(marker in read('submodules/TelegramCore/Sources/' + name), name)
        helper = read('submodules/TelegramCore/Sources/Arena/BananaBannedChats.swift')
        self.assertIn('transaction.getPeerChatListInclusion(updated.id) != .notIncluded', helper)

    def test_clipboard_work_is_cancelled_and_off_main(self):
        helper = read('submodules/GalleryUI/Sources/BananaMediaClipboard.swift')
        self.assertIn('deliverOn(Queue.concurrentDefaultQueue())', helper)
        self.assertIn('take(1)', helper)
        for name in ['ChatImageGalleryItem', 'UniversalVideoGalleryItem']:
            source = read('submodules/GalleryUI/Sources/Items/' + name + '.swift')
            self.assertIn('self.mediaClipboardDisposable.dispose()', source)
            self.assertIn('self.mediaClipboardDisposable.set(', source)
        video = read('submodules/GalleryUI/Sources/Items/UniversalVideoGalleryItem.swift')
        self.assertIn('!message.isCopyProtected() && !item.peerIsCopyProtected && message.paidContent == nil', video)

    def test_mp4_uses_real_video_track_and_preserves_file_coordination(self):
        source = read('submodules/ICloudResources/Sources/ICloudResources.swift')
        self.assertIn('asset.tracks(withMediaType: .video).first', source)
        self.assertIn('width.isFinite, height.isFinite', source)
        self.assertIn('coordinator.coordinate(with: [intent]', source)
        menu = read('submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift')
        self.assertIn('if let videoMetadata = item.videoMetadata', menu)
        self.assertIn('pathExtension.lowercased()', menu)

    def test_fallback_is_disclosed_and_private_posts_stay_private(self):
        settings = read('submodules/SettingsUI/Sources/ForkExtrasController.swift')
        self.assertIn('tikwm.com', settings)
        self.assertIn('sharing parameters and your IP address', settings)
        extractor = read('submodules/BananaLinkDownloader/Sources/BananaTikTokExtractor.swift')
        self.assertIn('.pageTooLarge, .tiktokPrivate:', extractor)
        self.assertIn('BananaMediaURLPolicy.isAllowed(url)', extractor)
        job = read('submodules/BananaLinkDownloader/Sources/BananaLinkDownloadJob.swift')
        self.assertIn('Self.maxCarouselPhotos', job)
        self.assertIn('try? FileManager.default.removeItem(at: directory)', job)

    def test_account_labels_and_gift_switch_round_trip(self):
        source = read('submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift')
        for name in ['disableGiftStarsRedirect', 'visualLabels']:
            self.assertIn('forKey: "' + name + '"', source)
            self.assertIn('try container.encode(self.' + name, source)
        runtime = read('submodules/TelegramUI/Sources/SharedAccountContext.swift')
        self.assertIn('BananaVisualLabels.update(settings.visualLabels)', runtime)
        self.assertIn('settings.visualLabels[accountPeerId ?? 0]', read('submodules/SettingsUI/Sources/ForkExtrasController.swift'))


@unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; executes in macOS CI')
class Behavioral(unittest.TestCase):
    def test_tiktok_sources_errors_cookies_and_sanitized_fallback(self):
        parts = ['import Foundation\nimport CoreFoundation\nimport CryptoKit\n']
        for name in ['LinkDownloadError', 'LinkDownloadModels', 'LinkDownloadLink', 'MediaURLPolicy', 'TikTokExtractor']:
            parts.append(stripped(read('submodules/BananaLinkDownloader/Sources/Banana' + name + '.swift')))
        parts.append(read('Tests/DonutOct18/tiktok.swift'))
        execute('\n'.join(parts))

    def test_preserved_bans_pins_rejoin_and_manual_deletion(self):
        fixture, cases = read('Tests/DonutOct18/banned.swift').split('// TEST CASES', 1)
        peers = read('submodules/TelegramCore/Sources/UpdatePeers.swift')
        exclusion = peers[peers.index('func isPeerHiddenByCollapsedCommunity'):peers.index('func updatePeerChatInclusionWithMinTimestamp')]
        execute('\n'.join(['import Foundation', fixture, stripped(read('submodules/TelegramCore/Sources/Arena/BananaBannedChats.swift')), exclusion, cases]))

    def test_other_session_online_does_not_create_offline_ping_pong(self):
        source = read('submodules/TelegramCore/Sources/State/ManagedAccountPresence.swift')
        constants = '\n'.join(re.findall(r'^private let ghost\w+.*$', source, re.M))
        methods = []
        for name in ['isOtherSessionOnline', 'resetOtherSessionState', 'answerServerReportedOnline', 'settleServerReportedOnline', 'takeOwnActionReport', 'followsUnpromptedOffline', 'handleServerReportedOffline']:
            start = source.index('    private func ' + name + '(')
            end = source.index('\n    }', start) + len('\n    }')
            methods.append(source[start:end].replace('private func', 'func', 1))
        fixture = read('Tests/DonutOct18/presence.swift')
        execute('import Foundation\n' + constants + '\n' + fixture.replace('// PRODUCTION METHODS', '\n'.join(methods)))


if __name__ == '__main__':
    unittest.main()
