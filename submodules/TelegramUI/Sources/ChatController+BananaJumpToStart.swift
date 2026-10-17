import Foundation
import UIKit
import Display
import ContextUI
import AccountContext
import TelegramUIPreferences

extension ChatControllerImpl {
    /// "Jump to start" for the menu of the chat's (or forum topic's) avatar: loads the start of the history and
    /// scrolls to the very first message. Adapted from Donutgram. Nil when Extras ▸ Messages switches it off.
    func bananaJumpToStartContextMenuItem() -> ContextMenuItem? {
        guard self.context.sharedContext.immediateForkExtrasSettings.jumpToStartInChatMenu else {
            return nil
        }
        let text = ForkPresentationLanguage.prefersRussianStrings ? "В начало чата" : "Jump to Start"
        return .action(ContextMenuActionItem(text: text, icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "arrow.up.to.line", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.0, weight: .regular)), color: theme.actionSheet.primaryTextColor)
        }, action: { [weak self] _, f in
            f(.dismissWithoutContent)
            self?.scrollToStartOfHistory()
        }))
    }
}
