import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences
import TelegramPresentationData
import UndoUI

// Read All from the chat list (after Donutgram): every unread chat at once, either read on the
// server or only on this device.
extension ChatListControllerImpl {
    func presentReadAllChats() {
        let russian = ForkPresentationLanguage.prefersRussianStrings
        let presentationData = self.presentationData
        var includeArchived = false

        // Reading on the server is what the user asks for here, so it goes out even when ghost
        // mode hides read receipts; the sheet says so.
        var text = russian ? "Отметить все чаты прочитанными? «Прочитать» сообщит отправителям, что вы прочитали их сообщения" : "Mark all chats as read? Mark as Read lets senders know you've read their messages"
        if ForkGhostModeSettings.suppressMessageReads {
            text += russian ? ", даже в режиме призрака." : ", even in Ghost Mode."
        } else {
            text += "."
        }
        text += russian ? " «Только на этом устройстве» уберёт счётчики здесь и ничего не отправит." : " Only on This Device clears the badges here and sends nothing."

        let actionSheet = ActionSheetController(presentationData: presentationData)
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: text, parseMarkdown: false),
                ActionSheetSwitchItem(title: russian ? "Включая архив" : "Include Archived Chats", isOn: false, action: { value in
                    includeArchived = value
                }),
                ActionSheetButtonItem(title: russian ? "Прочитать" : "Mark as Read", action: { [weak self, weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    self?.readAllChats(includeArchived: includeArchived, onServer: true)
                }),
                ActionSheetButtonItem(title: russian ? "Только на этом устройстве" : "Only on This Device", action: { [weak self, weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    self?.readAllChats(includeArchived: includeArchived, onServer: false)
                })
            ]),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        self.present(actionSheet, in: .window(.root))
    }

    private func readAllChats(includeArchived: Bool, onServer: Bool) {
        let engine = self.context.engine
        let _ = (engine.messages.bananaReadAllChatPeerIds(includeArchived: includeArchived, onServer: onServer)
        |> mapToSignal { peerIds -> Signal<(Int, Int), NoError> in
            if onServer {
                // Small batches a second apart: each chat is a request of its own, and hundreds at
                // once end in FLOOD_WAIT.
                let batchSize = 20
                var signal: Signal<Never, NoError> = .complete()
                for start in stride(from: 0, to: peerIds.count, by: batchSize) {
                    let batch = Array(peerIds[start ..< min(start + batchSize, peerIds.count)])
                    let read = engine.messages.togglePeersUnreadMarkInteractively(peerIds: batch, setToValue: false)
                    signal = signal |> then(start == 0 ? read : (read |> delay(1.0, queue: Queue.concurrentDefaultQueue())))
                }
                return signal
                |> map { _ -> (Int, Int) in }
                |> then(.single((peerIds.count, peerIds.count)))
            } else {
                return engine.messages.bananaReadChatsOnThisDevice(peerIds: peerIds)
                |> map { readCount -> (Int, Int) in
                    return (readCount, peerIds.count)
                }
            }
        }
        |> deliverOnMainQueue).startStandalone(next: { [weak self] readCount, totalCount in
            guard let self else {
                return
            }
            let russian = ForkPresentationLanguage.prefersRussianStrings
            let text: String
            if totalCount == 0 {
                text = russian ? "Непрочитанных чатов нет." : "There are no unread chats."
            } else if readCount < totalCount {
                text = russian ? "Прочитано на этом устройстве: \(readCount) из \(totalCount). Секретные чаты, форумы и некоторые другие остались непрочитанными." : "Read on this device: \(readCount) of \(totalCount). Secret chats, forums and a few others stay unread."
            } else if onServer {
                text = russian ? "Все чаты прочитаны: \(readCount)." : "All chats read: \(readCount)."
            } else {
                text = russian ? "Прочитано на этом устройстве: \(readCount)." : "Read on this device: \(readCount)."
            }
            self.present(UndoOverlayController(presentationData: self.presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), in: .current)
        })
    }
}
