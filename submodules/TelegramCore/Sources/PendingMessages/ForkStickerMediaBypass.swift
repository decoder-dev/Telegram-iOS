// Fork: send stickers as short silent videos in chats that ban stickers but still allow videos.
// Ported from Donutgram (kittenello/Donutgram 9b62a5089c, ee069f97b3 and their fixes, "DonutgramStickerMedia.swift");
// gated by Extras > Messages > Sending > "Bypass sticker restrictions". The conversion itself needs UIKit and
// AVFoundation and lives in TelegramUI (ChatController+ForkStickerMedia.swift).
import Foundation
import Postbox
import SwiftSignalKit

/// "Bypass sticker restrictions", projected from Extras. Persisted like the other chat flags, so a send right after a
/// cold launch sees the stored value before the settings arrive.
public enum ForkStickerBypassSettings {
    private static let persistedKey = "ForkStickerBypassSettings.enabled.v1"
    private static let value = Atomic<Bool>(value: UserDefaults.standard.bool(forKey: persistedKey))
    public static var enabled: Bool {
        get { return value.with { $0 } }
        set {
            let previous = value.swap(newValue)
            if previous != newValue {
                UserDefaults.standard.set(newValue, forKey: persistedKey)
            }
        }
    }
}

/// True when the setting is on and `peer` bans stickers while still allowing media and videos, so a sticker (`file`,
/// when given, must be one) can go out as a short silent video instead. Admins and creators are never banned, so they
/// never convert.
public func forkCanSendStickerAsMedia(peer: Peer?, file: TelegramMediaFile? = nil) -> Bool {
    guard ForkStickerBypassSettings.enabled else {
        return false
    }
    let isBanned: (TelegramChatBannedRightsFlags) -> Bool
    if let channel = peer as? TelegramChannel {
        isBanned = { channel.hasBannedPermission($0) != nil }
    } else if let group = peer as? TelegramGroup {
        isBanned = { group.hasBannedPermission($0) }
    } else {
        return false
    }
    guard isBanned(.banSendStickers), !isBanned(.banSendMedia), !isBanned(.banReadMessages), !isBanned(.banSendVideos) else {
        return false
    }
    if let file, !file.isSticker {
        return false
    }
    return true
}
