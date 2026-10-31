import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences
import AccountContext

// The account capacity does not depend on Premium status.
public let maximumForkNumberOfAccounts = 500
public let maximumNumberOfAccounts = maximumForkNumberOfAccounts
public let maximumPremiumNumberOfAccounts = maximumForkNumberOfAccounts

public func activeAccountsAndPeers(context: AccountContext, includePrimary: Bool = false) -> Signal<((AccountContext, EnginePeer)?, [(AccountContext, EnginePeer, Int32)]), NoError> {
    let sharedContext = context.sharedContext
    return context.sharedContext.activeAccountContexts
    |> mapToSignal { primary, activeAccounts, _ -> Signal<((AccountContext, EnginePeer)?, [(AccountContext, EnginePeer, Int32)]), NoError> in
        var accounts: [Signal<(AccountContext, EnginePeer, Int32, Bool)?, NoError>] = []
        func accountWithPeer(_ context: AccountContext) -> Signal<(AccountContext, EnginePeer, Int32, Bool)?, NoError> {
            return combineLatest(
                context.account.postbox.peerView(id: context.account.peerId),
                renderedTotalUnreadCount(accountManager: sharedContext.accountManager, engine: context.engine),
                accountIsHiddenSignal(context: context)
            )
            |> map { view, totalUnreadCount, isHidden -> (EnginePeer?, Int32, Bool) in
                return (view.peers[view.peerId].flatMap(EnginePeer.init), totalUnreadCount.0, isHidden)
            }
            |> distinctUntilChanged { lhs, rhs in
                if lhs.0 != rhs.0 {
                    return false
                }
                if lhs.1 != rhs.1 {
                    return false
                }
                if lhs.2 != rhs.2 {
                    return false
                }
                return true
            }
            |> map { peer, totalUnreadCount, isHidden -> (AccountContext, EnginePeer, Int32, Bool)? in
                if let peer = peer {
                    return (context, peer, totalUnreadCount, isHidden)
                } else {
                    return nil
                }
            }
        }
        for (_, context, _) in activeAccounts {
            accounts.append(accountWithPeer(context))
        }
        
        return combineLatest(combineLatest(accounts), HiddenAccountsSession.shared.stateSignal)
        |> map { accounts, hiddenState -> ((AccountContext, EnginePeer)?, [(AccountContext, EnginePeer, Int32)]) in
            var primaryRecord: (AccountContext, EnginePeer)?
            if let first = accounts.filter({ $0?.0.account.id == primary?.account.id }).first, let (account, peer, _, _) = first {
                primaryRecord = (account, peer)
            }
            let listedAccounts = includePrimary ? accounts : accounts.filter({ $0?.0.account.id != primary?.account.id })
            var accountRecords: [(AccountContext, EnginePeer, Int32)] = []
            for case let (account, peer, unreadCount, isHidden)? in listedAccounts {
                // The account on screen is always listed: it is open, so hiding it from itself protects nothing.
                if account.account.id == primary?.account.id {
                    accountRecords.append((account, peer, unreadCount))
                    continue
                }
                switch hiddenState.listing(accountId: account.account.id.int64, isHidden: isHidden) {
                case .some(.normal):
                    accountRecords.append((account, peer, unreadCount))
                case .some(.locked):
                    // Revealed by Settings × 10 but not opened: its unread count would say what is in it.
                    accountRecords.append((account, peer, 0))
                case .none:
                    break
                }
            }
            return (primaryRecord, accountRecords)
        }
    }
}

/// Whether this account hides itself (`ChatArchiveSettings.isAccountHidden`).
public func accountIsHiddenSignal(context: AccountContext) -> Signal<Bool, NoError> {
    return context.engine.data.subscribe(
        TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: ApplicationSpecificPreferencesKeys.chatArchiveSettings)
    )
    |> map { preference -> Bool in
        return (preference?.get(ChatArchiveSettings.self) ?? .default).isAccountHidden
    }
    |> distinctUntilChanged
}
