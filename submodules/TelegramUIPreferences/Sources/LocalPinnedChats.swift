import Foundation
import SwiftSignalKit
import TelegramCore

/// Chats pinned on this device only, once the server's pinned chat limit is reached ("Pin Beyond the Limit" in Extras).
/// Per account, newest first; All Chats lists them right under the chats the server pinned.
public struct LocalPinnedChats: Codable, Equatable {
    public var peerIds: [EnginePeer.Id]

    public static var `default`: LocalPinnedChats {
        return LocalPinnedChats(peerIds: [])
    }

    public init(peerIds: [EnginePeer.Id]) {
        self.peerIds = peerIds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        let values = try container.decodeIfPresent([Int64].self, forKey: "peerIds") ?? []
        self.peerIds = values.map(EnginePeer.Id.init)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode(self.peerIds.map { $0.toInt64() }, forKey: "peerIds")
    }
}

public func localPinnedChatIds(engine: TelegramEngine) -> Signal<[EnginePeer.Id], NoError> {
    return engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: ApplicationSpecificPreferencesKeys.localPinnedChats))
    |> map { entry -> [EnginePeer.Id] in
        return entry?.get(LocalPinnedChats.self)?.peerIds ?? []
    }
    |> distinctUntilChanged
}

public func updateLocalPinnedChatIds(engine: TelegramEngine, _ f: @escaping ([EnginePeer.Id]) -> [EnginePeer.Id]) -> Signal<Never, NoError> {
    return engine.preferences.update(id: ApplicationSpecificPreferencesKeys.localPinnedChats, { entry in
        let current = entry?.get(LocalPinnedChats.self) ?? .default
        return SharedPreferencesEntry(LocalPinnedChats(peerIds: f(current.peerIds)))
    })
}
