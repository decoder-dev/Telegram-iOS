import Foundation
import UIKit
import AccountContext
import Display
import TelegramPresentationData
import TelegramCore
import UndoUI

public func arenaToggleShadowBan(context: AccountContext, peer: EnginePeer, present: @escaping (ViewController) -> Void) {
    let peerId = peer.id.toInt64()
    let isBanned = ArenaSettings.shared.isShadowBanned(peerId)
    ArenaSettings.shared.setShadowBanned(!isBanned, peerId: peerId)
    
    let text = arenaShadowBanString(!isBanned ? "Добавлен в теневой бан" : "Удален из теневого бана", strings: context.sharedContext.currentPresentationData.with { $0 }.strings)
    
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let controller = UndoOverlayController(
        presentationData: presentationData,
        content: .universal(
            animation: !isBanned ? "anim_block" : "anim_unblock",
            scale: 0.075,
            colors: [:],
            title: nil,
            text: text,
            customUndoText: nil,
            timeout: nil
        ),
        elevatedLayout: false,
        animateInAsReplacement: false,
        action: { _ in return false }
    )
    present(controller)
}

public func dgToggleShadowBan(context: AccountContext, peer: EnginePeer, present: @escaping (ViewController) -> Void) {
    arenaToggleShadowBan(context: context, peer: peer, present: present)
}

