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
        var accounts: [Signal<(AccountContext, EnginePeer, Int32)?, NoError>] = []
        func accountWithPeer(_ context: AccountContext) -> Signal<(AccountContext, EnginePeer, Int32)?, NoError> {
            return combineLatest(context.account.postbox.peerView(id: context.account.peerId), renderedTotalUnreadCount(accountManager: sharedContext.accountManager, engine: context.engine))
            |> map { view, totalUnreadCount -> (EnginePeer?, Int32) in
                return (view.peers[view.peerId].flatMap(EnginePeer.init), totalUnreadCount.0)
            }
            |> distinctUntilChanged { lhs, rhs in
                if lhs.0 != rhs.0 {
                    return false
                }
                if lhs.1 != rhs.1 {
                    return false
                }
                return true
            }
            |> map { peer, totalUnreadCount -> (AccountContext, EnginePeer, Int32)? in
                if let peer = peer {
                    return (context, peer, totalUnreadCount)
                } else {
                    return nil
                }
            }
        }
        for (_, context, _) in activeAccounts {
            accounts.append(accountWithPeer(context))
        }
        
        return combineLatest(combineLatest(accounts), hiddenAccountsSettings(accountManager: sharedContext.accountManager), HiddenAccountsSession.shared.stateSignal)
        |> map { accounts, hiddenSettings, hiddenState -> ((AccountContext, EnginePeer)?, [(AccountContext, EnginePeer, Int32)]) in
            var primaryRecord: (AccountContext, EnginePeer)?
            if let first = accounts.filter({ $0?.0.account.id == primary?.account.id }).first, let (account, peer, _) = first {
                primaryRecord = (account, peer)
            }
            let listedAccounts = includePrimary ? accounts : accounts.filter({ $0?.0.account.id != primary?.account.id })
            var accountRecords: [(AccountContext, EnginePeer, Int32)] = []
            for case let (account, peer, unreadCount)? in listedAccounts {
                let accountId = account.account.id.int64
                // The account on screen is always listed: it is open, so hiding it from itself protects nothing.
                if account.account.id == primary?.account.id {
                    accountRecords.append((account, peer, unreadCount))
                    continue
                }
                // Before the session has checked the owners, the stored settings decide: a hidden account must not
                // flash into the list at launch.
                if !hiddenState.isResolved {
                    if !hiddenSettings.isHidden(accountId) {
                        accountRecords.append((account, peer, unreadCount))
                    }
                    continue
                }
                switch hiddenState.listing(accountId: accountId) {
                case .some(.normal):
                    accountRecords.append((account, peer, unreadCount))
                case .some(.locked):
                    // Revealed by its owner's Settings × 10 but not opened: its unread count would say what is in it.
                    accountRecords.append((account, peer, 0))
                case .none:
                    break
                }
            }
            return (primaryRecord, accountRecords)
        }
    }
}
