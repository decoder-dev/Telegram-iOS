import Foundation
import Postbox
import SwiftSignalKit

/// Donutgram "hide service messages": the history leaves out notices about who joined or left and edits of the chat.
/// Read by the history node when it builds its entries, so it is projected there from the settings before the history
/// re-emits. Mirrored to UserDefaults so the first chat opened after a cold launch already honours the stored choice.
public enum ForkServiceMessageSettings {
    private static let persistedKey = "ForkServiceMessageSettings.hidden.v1"
    private static let value = Atomic<Bool>(value: UserDefaults.standard.bool(forKey: persistedKey))
    public static var hidden: Bool {
        get { return value.with { $0 } }
        set {
            let previous = value.swap(newValue)
            if previous != newValue {
                UserDefaults.standard.set(newValue, forKey: persistedKey)
            }
        }
    }
}

/// Whether the service-message filter hides `message`: notices about who joined or left, edits of the chat (title, photo,
/// theme, pin, timers) and of polls and to-do lists. Calls, gifts, payments, giveaways, suggested posts and anything else
/// a person acts on stay visible, as does every action added later.
public func forkIsHideableServiceMessage(_ message: Message) -> Bool {
    for media in message.media {
        guard let action = media as? TelegramMediaAction else {
            continue
        }
        switch action.action {
        case .addedMembers, .removedMembers, .joinedByLink, .joinedByRequest, .joinedChannel, .joinedViaCommunity, .peerJoined,
             .groupCreated, .titleUpdated, .photoUpdated, .pinnedMessageUpdated, .channelMigratedFromGroup, .groupMigratedToChannel,
             .historyCleared, .messageAutoremoveTimeoutUpdated, .setChatTheme, .setChatWallpaper, .setSameChatWallpaper,
             .topicEdited, .boostsApplied, .paidMessagesPriceEdited, .groupCreatorChange, .copyProtectionToggle, .communityChanged,
             .pollOptionAppended, .pollOptionDeleted, .todoCompletions, .todoAppendTasks:
            return true
        default:
            return false
        }
    }
    return false
}
