let account = PeerId(Int64.random(in: 1_000_000 ... 9_000_000))
let otherAccount = PeerId(account.value + 1)
let peer = PeerId(42)
defer {
    TelegramSimpleSettings.shared.setGhostLocalRead(nil, accountPeerId: account.value, peerId: peer.value)
}
let transaction = Transaction()
let server = PeerReadState.idBased(maxIncomingReadId: 10, maxOutgoingReadId: 0, maxKnownId: 20, count: 10, markedUnread: false)
transaction.states[peer] = server
let index = MessageIndex(id: MessageId(peerId: peer, namespace: 0, id: 20))
transaction.operations[peer] = .Push
precondition(!bananaApplyGhostLocalRead(transaction: transaction, accountPeerId: account, index: index))
precondition(transaction.states[peer] == server)
transaction.operations[peer] = nil
transaction.forum = true
precondition(!bananaApplyGhostLocalRead(transaction: transaction, accountPeerId: account, index: index))
transaction.forum = false
precondition(bananaApplyGhostLocalRead(transaction: transaction, accountPeerId: account, index: index))
precondition(transaction.states[peer]?.isUnread == false)
precondition(transaction.operations[peer] == nil)
precondition(bananaGhostLocalReadState(accountPeerId: otherAccount, peerId: peer) == nil)
bananaResetIncomingReadStates(transaction: transaction, accountPeerId: account, [peer: [0: server]])
precondition(transaction.states[peer]?.isUnread == false, "Server sync lost local read")
bananaGhostLocalReadWillReadOnServer(transaction: transaction, accountPeerId: account, peerId: peer)
precondition(transaction.states[peer] == server)
precondition(bananaGhostLocalReadState(accountPeerId: account, peerId: peer) == nil)
precondition(bananaApplyGhostLocalRead(transaction: transaction, accountPeerId: account, index: index))
ForkGhostModeSettings.suppressMessageReads = false
bananaRestoreGhostLocalReads(transaction: transaction, accountPeerId: account)
precondition(transaction.states[peer] == server)
precondition(transaction.operations[peer] == .Validate, "Restore must verify counts after deletions/holes")
precondition(!TelegramSimpleSettings.shared.hasGhostLocalReads(accountPeerId: account.value))
print("Ghost local read: account isolation, pending push, forums, sync and restore passed")

// Disabling only a chat exception must restore that chat while global Ghost stays enabled.
ForkGhostModeSettings.suppressMessageReads = true
transaction.operations[peer] = nil
precondition(bananaApplyGhostLocalRead(transaction: transaction, accountPeerId: account, index: index))
bananaRestoreGhostLocalReads(transaction: transaction, accountPeerId: account)
precondition(bananaGhostLocalReadState(accountPeerId: account, peerId: peer) != nil)
ForkGhostModeSettings.exceptions = [peer]
bananaRestoreGhostLocalReads(transaction: transaction, accountPeerId: account)
precondition(transaction.states[peer] == server)
precondition(transaction.operations[peer] == .Validate)
precondition(bananaGhostLocalReadState(accountPeerId: account, peerId: peer) == nil)
ForkGhostModeSettings.exceptions = []
// A delta recorded before an incoming-message deletion is not trusted as the final count.
transaction.operations[peer] = nil
precondition(bananaApplyGhostLocalRead(transaction: transaction, accountPeerId: account, index: index))
ForkGhostModeSettings.suppressMessageReads = false
bananaRestoreGhostLocalReads(transaction: transaction, accountPeerId: account)
precondition(transaction.operations[peer] == .Validate)
let authoritative = PeerReadState.idBased(maxIncomingReadId: 10, maxOutgoingReadId: 0, maxKnownId: 20, count: 9, markedUnread: false)
bananaResetIncomingReadStates(transaction: transaction, accountPeerId: account, [peer: [0: authoritative]])
precondition(transaction.states[peer] == authoritative, "Authoritative count must replace local estimate")
print("Ghost local read: exception restore and authoritative count reconciliation passed")
