import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences

/// Fork (Regram): after a successful join of a group or channel, offer to add it to one of the existing chat folders.
/// Not called for join requests (nothing was joined). Does nothing while the setting is off or when no folder can take the chat.
public func forkOfferFolderAfterJoin(context: AccountContext, peerId: EnginePeer.Id) {
    guard context.sharedContext.immediateForkExtrasSettings.chooseFolderAfterJoin else {
        return
    }
    let _ = (context.engine.peers.currentChatListFilters()
    |> take(1)
    |> deliverOnMainQueue).startStandalone(next: { filters in
        var candidates: [(id: Int32, title: String)] = []
        for filter in filters {
            if case let .filter(id, title, _, data) = filter {
                var updatedData = data
                if updatedData.addIncludePeer(peerId: peerId) {
                    candidates.append((id, title.text))
                }
            }
        }
        if candidates.isEmpty {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let russian = ForkPresentationLanguage.prefersRussianStrings
        let controller = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        items.append(ActionSheetTextItem(title: russian ? "Добавить в папку" : "Add to folder", parseMarkdown: false))
        for candidate in candidates {
            let folderId = candidate.id
            items.append(ActionSheetButtonItem(title: candidate.title, color: .accent, action: { [weak controller] in
                controller?.dismissAnimated()
                let _ = (context.engine.peers.updateChatListFiltersInteractively { filters in
                    var filters = filters
                    for i in 0 ..< filters.count {
                        if filters[i].id == folderId, case let .filter(id, title, emoticon, data) = filters[i] {
                            var updatedData = data
                            let _ = updatedData.addIncludePeer(peerId: peerId)
                            filters[i] = .filter(id: id, title: title, emoticon: emoticon, data: updatedData)
                            break
                        }
                    }
                    return filters
                }).startStandalone()
            }))
        }
        controller.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak controller] in
                controller?.dismissAnimated()
            })
        ])])
        context.sharedContext.presentGlobalController(controller, nil)
    })
}
