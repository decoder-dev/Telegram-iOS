import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import TelegramUIPreferences
import PresentationDataUtils

extension ChatControllerImpl {
    /// "Confirm reactions before joining": adding `reaction` in a channel or group the account has not joined is asked
    /// about first. Removing a reaction never is, and Stars reactions have their own confirmation. Adapted from Donutgram.
    func forkReactionNeedsConfirmation(_ reaction: MessageReaction.Reaction) -> Bool {
        guard self.context.sharedContext.immediateForkExtrasSettings.confirmReactionsInUnjoinedChats else {
            return false
        }
        if case .stars = reaction {
            return false
        }
        guard let channel = self.presentationInterfaceState.renderedPeer?.peer as? TelegramChannel else {
            return false
        }
        return channel.participationStatus != .member
    }

    /// Asks whether to react in a chat that has not been joined, and runs `apply` on "Yes".
    func forkPresentReactionConfirmation(apply: @escaping () -> Void) {
        let presentationData = self.presentationData
        let text = ForkPresentationLanguage.prefersRussianStrings ? "Вы точно хотите поставить реакцию в чате, в который еще не вступили?" : "Do you want to react in a chat you haven't joined?"
        self.present(textAlertController(context: self.context, title: nil, text: text, actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_No, action: {}),
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Yes, action: apply)
        ]), in: .window(.root))
    }

    /// A tap on a previewed chat opens it. With "Confirm entering a chat preview" it asks first, over the preview, which
    /// stays open on "No". Message option previews (forward, reply) are not chats being entered and never ask.
    func openFromPreviewing() {
        var asks = self.context.sharedContext.immediateForkExtrasSettings.confirmChatPreviewEntry
        if let subject = self.subject, case .messageOptions = subject {
            asks = false
        }
        guard asks else {
            self.animateFromPreviewing()
            return
        }
        if self.forkPreviewEntryAlert != nil {
            return
        }
        let presentationData = self.presentationData
        let text = ForkPresentationLanguage.prefersRussianStrings ? "Вы точно хотите перейти в этот чат?" : "Do you want to open this chat?"
        let alert = textAlertController(context: self.context, title: nil, text: text, actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_No, action: {}),
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Yes, action: { [weak self] in
                self?.animateFromPreviewing()
            })
        ])
        self.forkPreviewEntryAlert = alert
        // The preview is a context menu in the global overlay: an alert in the root window would open under it.
        self.presentInGlobalOverlay(alert)
    }
}
