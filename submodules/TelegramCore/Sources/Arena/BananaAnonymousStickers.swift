import Foundation
import Postbox
import SwiftSignalKit

/// Fork (Donutgram): "Send stickers anonymously". A sticker goes out as a plain uploaded document without the
/// reference to its set, so nobody who gets it can open the set or see which one the sender uses. The server's copy
/// has no set, so the sender keeps it here, by the id of the file the server made, to open it from their own chat.
public enum BananaAnonymousStickers {
    private static let enabledState = Atomic<Bool>(value: false)
    private static let lock = NSLock()
    private static let capacity = 500

    public static var enabled: Bool {
        get { return enabledState.with { $0 } }
        set { let _ = enabledState.swap(newValue) }
    }

    private struct Entry: Codable {
        var fileId: Int64
        var reference: StickerPackReference
    }

    private static func key(accountPeerId: PeerId) -> String {
        return "Banana.anonymousStickerPacks.\(accountPeerId.toInt64())"
    }

    private static func load(accountPeerId: PeerId) -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: self.key(accountPeerId: accountPeerId)) else {
            return []
        }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    /// The set of a sticker this account sent anonymously, or nil for any other file.
    public static func stickerPack(accountPeerId: PeerId, file: TelegramMediaFile) -> StickerPackReference? {
        guard file.isSticker, file.fileId.namespace == Namespaces.Media.CloudFile else {
            return nil
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.load(accountPeerId: accountPeerId).first(where: { $0.fileId == file.fileId.id })?.reference
    }

    /// Keeps `reference` for `file`, the server's copy of a sticker sent without it.
    static func save(_ reference: StickerPackReference, accountPeerId: PeerId, file: TelegramMediaFile) {
        guard file.fileId.namespace == Namespaces.Media.CloudFile else {
            return
        }
        switch reference {
        case .id, .name:
            break
        default:
            return
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        var entries = self.load(accountPeerId: accountPeerId)
        entries.removeAll(where: { $0.fileId == file.fileId.id })
        entries.append(Entry(fileId: file.fileId.id, reference: reference))
        if entries.count > self.capacity {
            entries.removeFirst(entries.count - self.capacity)
        }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: self.key(accountPeerId: accountPeerId))
        }
    }

    /// Whether `file`, sent to `peerId`, goes out without its set.
    static func appliesTo(file: TelegramMediaFile, peerId: PeerId) -> Bool {
        return self.enabled && file.isSticker && peerId.namespace != Namespaces.Peer.SecretChat
    }
}
