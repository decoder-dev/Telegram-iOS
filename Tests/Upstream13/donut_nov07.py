"""Donutgram commits of 2026-10-31..11-07, ported: the grey band on a shared profile photo (7f969eda1b, edcb11ccb6)
and "Hide AI features" (9b62a5089c, c96a7c82af, f77d1438b7). Source-text assertions; the Swift is verified by the full
Bazel build."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


CONTROLLER = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
SHARED = 'submodules/TelegramUI/Sources/SharedAccountContext.swift'
HISTORY = 'submodules/TelegramUI/Sources/ChatHistoryListNode.swift'
BUBBLE = 'submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift'
TEXT_BUBBLE = 'submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift'
MENUS = 'submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift'


class SharedProfilePhoto(unittest.TestCase):
    def test_cloud_photo_data_is_not_reused_for_a_new_server_resource(self):
        source = read('submodules/TelegramCore/Sources/State/ApplyUpdateMessage.swift')
        body = source.split('private func canReusePhotoResourceData(', 1)[1].split('\n}\n', 1)[0]
        self.assertIn('fromResource.id != toResource.id', body)
        self.assertIn('CloudPeerPhotoSizeMediaResource', body)
        self.assertIn('CloudPhotoSizeMediaResource', body)
        self.assertEqual(source.count('canReusePhotoResourceData(from: from'), 2)

    def test_a_complete_file_of_another_encoding_is_decoded_whole(self):
        source = read('submodules/PhotoResources/Sources/PhotoResources.swift')
        helper = source.split('private func completePhotoResourceData(', 1)[1].split('\n}\n', 1)[0]
        self.assertIn('guard data.complete, data.size != progressiveSize else', helper)
        self.assertIn('completePhotoResourceData(data, progressiveSize: Int64(progressiveRepresentation.progressiveSizes.last!))', source)
        # The force unwrap is safe only inside the progressive branch, which needs more than one size.
        branch = source.split('let progressiveRepresentation = progressiveImageRepresentation(photoReference.media.representations), progressiveRepresentation.progressiveSizes.count > 1', 1)[1]
        self.assertIn('completePhotoResourceData(data, progressiveSize:', branch.split('if !forceThumbnail || photoReference.media.immediateThumbnailData == nil', 1)[0])


class HideAIFeatures(unittest.TestCase):
    def test_the_input_panel_switch_names_all_ai_features(self):
        controller = read(CONTROLLER)
        self.assertIn('.appearanceToggle(2101, russian ? "Скрыть функции ИИ" : "Hide AI features", settings.hideAIButton, \\.hideAIButton)', controller)
        self.assertIn('Hide AI features removes the AI buttons and message summaries', controller)

    def test_the_flag_is_projected_before_the_history_re_emits(self):
        self.assertIn('ForkAIFeaturesSettings.hidden = settings.hideAIButton', read(SHARED))
        history = read(HISTORY)
        mapping = history.split('let messageFilterSettings: Signal<MessageFilterSettingsFingerprint, NoError>', 1)[1].split('|> distinctUntilChanged', 1)[0]
        self.assertIn('ForkAIFeaturesSettings.hidden = settings.hideAIButton', mapping)
        self.assertIn('hidesAIFeatures: settings.hideAIButton', mapping)

    def test_bubbles_offer_and_show_no_summary_while_hidden(self):
        bubble = read(BUBBLE)
        self.assertIn('if !ForkAIFeaturesSettings.hidden, let _ = item.message.attributes.first(where: { $0 is SummarizationMessageAttribute }) {\n                needsSummarizeButton = true', bubble)
        self.assertEqual(bubble.count('!ForkAIFeaturesSettings.hidden && item.controllerInteraction.summarizedMessageIds.contains(item.message.id)'), 2)
        self.assertIn('!ForkAIFeaturesSettings.hidden && item.controllerInteraction.summarizedMessageIds.contains(item.message.id)', read(TEXT_BUBBLE))

    def test_copy_takes_the_original_text_while_hidden(self):
        menus = read(MENUS)
        self.assertEqual(menus.count('if !ForkAIFeaturesSettings.hidden, controllerInteraction.summarizedMessageIds.contains(message.id)'), 4)
        self.assertNotIn('if controllerInteraction.summarizedMessageIds.contains(message.id)', menus)

    def test_ai_compose_and_open_summaries_go_away(self):
        node = read('submodules/TelegramUI/Sources/ChatControllerNode.swift')
        self.assertIn('func openAICompose() {\n        guard !ForkAIFeaturesSettings.hidden else {', node)
        controller = read('submodules/TelegramUI/Sources/ChatController.swift')
        self.assertIn('self.controllerInteraction?.summarizedMessageIds.removeAll()', controller)


if __name__ == '__main__':
    unittest.main()
