import Foundation
import UIKit
import AccountContext
import Display
import TelegramCore
import UndoUI

public func dgToggleShadowBan(context: AccountContext, peer: EnginePeer, present: @escaping (ViewController) -> Void) {
    let peerId = peer.id.toInt64()
    let isBanned = ArenaSettings.shared.isShadowBanned(peerId)
    ArenaSettings.shared.setShadowBanned(!isBanned, peerId: peerId)
    
    let text = !isBanned ? "Добавлен в теневой бан" : "Удален из теневого бана"
    
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
