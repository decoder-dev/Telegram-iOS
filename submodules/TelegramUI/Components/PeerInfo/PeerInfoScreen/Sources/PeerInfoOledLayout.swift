import Foundation
import UIKit
import TelegramPresentationData
import TelegramCore

func peerInfoUsesOledCardLayout(presentationData: PresentationData, isSettings: Bool, isMyProfile: Bool) -> Bool {
    return presentationData.theme.overallDarkAppearance && !isSettings && !isMyProfile
}

let peerInfoOledCardBackgroundColor = UIColor(rgb: 0x1C1C1E)
let peerInfoOledActionButtonBackgroundColor = UIColor(rgb: 0x2C2C2E)
let peerInfoOledCardLabelColor = UIColor(rgb: 0xAEAEB2)
let peerInfoOledCardFooterColor = UIColor(rgb: 0x636366)

struct PeerInfoHeaderButtonContent {
    let text: String
    let icon: PeerInfoHeaderButtonIcon
}

func peerInfoHeaderButtonContent(
    key: PeerInfoHeaderButtonKey,
    presentationData: PresentationData,
    peer: EnginePeer?,
    peerNotificationSettings: TelegramPeerNotificationSettings?,
    threadNotificationSettings: TelegramPeerNotificationSettings?,
    globalNotificationSettings: EngineGlobalNotificationSettings?
) -> PeerInfoHeaderButtonContent {
    switch key {
    case .message:
        return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonMessage, icon: .message)
    case .discussion:
        return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonDiscuss, icon: .message)
    case .call:
        return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonCall, icon: .call)
    case .videoCall:
        return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonVideoCall, icon: .videoCall)
    case .voiceChat:
        if case let .channel(channel) = peer, case .broadcast = channel.info {
            return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonLiveStream, icon: .voiceChat)
        } else {
            return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonVoiceChat, icon: .voiceChat)
        }
    case .mute:
        let chatIsMuted = peerInfoIsChatMuted(peer: peer, peerNotificationSettings: peerNotificationSettings, threadNotificationSettings: threadNotificationSettings, globalNotificationSettings: globalNotificationSettings)
        if chatIsMuted {
            return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonUnmute, icon: .unmute)
        } else {
            return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonMute, icon: .mute)
        }
    case .more:
        return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonMore, icon: .more)
    case .addMember:
        return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonAddMember, icon: .addMember)
    case .search:
        return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonSearch, icon: .search)
    case .leave:
        return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonLeave, icon: .leave)
    case .stop:
        return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonStop, icon: .stop)
    case .addContact:
        fatalError()
    }
}
