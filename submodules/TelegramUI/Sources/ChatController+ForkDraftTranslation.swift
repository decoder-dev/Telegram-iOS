import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramUIPreferences
import TextFormat
import UndoUI
import TranslateUI
import ChatSendMessageActionUI

extension ChatControllerImpl {
    /// Translate Before Sending (from Swiftgram): the send menu's translation items for the current draft. Nil when the
    /// switch is off, the draft is empty or holds blocks plain text cannot carry (tables, headings), and in secret
    /// chats, whose text never leaves the device.
    func forkDraftTranslation() -> SendMessageActionSheetControllerParams.DraftTranslation? {
        let settings = self.context.sharedContext.immediateForkExtrasSettings
        guard settings.translateBeforeSending, let peerId = self.chatLocation.peerId, peerId.namespace != Namespaces.Peer.SecretChat else {
            return nil
        }
        let inputState = self.presentationInterfaceState.interfaceState.composeInputState
        guard inputState.content.isEntityExpressible(), !inputState.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let language = settings.draftTranslationLanguages[peerId.toInt64()]
        return SendMessageActionSheetControllerParams.DraftTranslation(
            languageTitle: language.flatMap { forkTranslateToTitle(strings: self.presentationData.strings, language: $0) },
            translate: { [weak self] in
                if let language {
                    self?.forkTranslateDraft(toLang: language)
                }
            },
            chooseLanguage: { [weak self] in
                guard let self else {
                    return
                }
                self.push(forkDraftTranslationLanguageController(context: self.context, selectedLanguage: language, completion: { [weak self] code in
                    self?.forkTranslateDraft(toLang: code)
                }))
            }
        )
    }

    /// Replaces the draft with its translation into `toLang` and remembers the language for this chat. Telegram keeps
    /// the formatting and custom emoji; Google, DeepL and Yandex return plain text.
    private func forkTranslateDraft(toLang: String) {
        guard let peerId = self.chatLocation.peerId else {
            return
        }
        let original = self.presentationInterfaceState.interfaceState.composeInputState
        let originalText = original.inputText
        if originalText.string.isEmpty {
            return
        }

        let _ = updateForkExtrasSettingsInteractively(accountManager: self.context.sharedContext.accountManager, { current in
            var updated = current
            updated.draftTranslationLanguages[peerId.toInt64()] = toLang
            return updated
        }).startStandalone()

        let russian = ForkPresentationLanguage.prefersRussianStrings
        let _ = (forkTranslateText(context: self.context, text: originalText.string, entities: generateChatInputTextEntities(originalText), toLang: toLang)
        |> deliverOnMainQueue).startStandalone(next: { [weak self] result in
            guard let self else {
                return
            }
            // The user went on typing, or started editing a message, while the request ran: their text wins.
            let interfaceState = self.presentationInterfaceState.interfaceState
            guard interfaceState.editMessage == nil, interfaceState.composeInputState.inputText.string == originalText.string else {
                return
            }
            let translated = ChatTextInputState(inputText: chatInputStateStringWithAppliedEntities(result.0, entities: result.1))
            // The input panel's own path, so the keyboard's Undo also brings the original back.
            self.interfaceInteraction?.updateTextInputStateAndMode { _, inputMode in
                return (translated, inputMode)
            }
            let icon = generateTintedImage(image: UIImage(bundleImageName: "Chat/Title Panels/Translate"), color: .white)
            self.present(UndoOverlayController(presentationData: self.presentationData, content: .image(image: icon ?? UIImage(), title: nil, text: russian ? "Текст переведён" : "Text translated", round: false, undoText: self.presentationData.strings.Undo_Undo), elevatedLayout: false, animateInAsReplacement: false, action: { [weak self] action in
                if case .undo = action {
                    self?.interfaceInteraction?.updateTextInputStateAndMode { current, inputMode in
                        if current.inputText.string == translated.inputText.string {
                            return (original, inputMode)
                        }
                        return (current, inputMode)
                    }
                }
                return true
            }), in: .current)
        }, error: { [weak self] _ in
            guard let self else {
                return
            }
            self.present(UndoOverlayController(presentationData: self.presentationData, content: .info(title: nil, text: russian ? "Не удалось перевести текст." : "Couldn't translate the text.", timeout: nil, customUndoText: nil), elevatedLayout: false, animateInAsReplacement: false, action: { _ in true }), in: .current)
        })
    }
}
