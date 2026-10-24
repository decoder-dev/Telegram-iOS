import Foundation
internal import TelegramApi
import Postbox
import SwiftSignalKit
import MtProtoKit

private typealias SignalKitTimer = SwiftSignalKit.Timer

// Donutgram: the server shows the user online after some own actions (sending a message,
// reading a chat, ...). Ghost mode answers each of them with an offline packet (see
// BananaPresenceSettings.requestGhostOffline); while the app is in front this timer backs them
// up for actions nothing reports.
private let ghostOfflineFallbackInterval: Double = 30.0

// Donutgram: a report of the account online that may come from another session is weighed this
// long after it arrives, so an action here that caused it has asked for its offline packet by then
// (see AccountPresenceManagerImpl.answerServerReportedOnline).
private let ghostServerOnlineSettleDelay: Double = 3.0
// Donutgram: an action here this long before the server reports the account online is what caused it.
private let ghostOwnActionWindow: Double = 5.0
// Donutgram: the server showing the account online again this soon after an offline packet no
// action here asked for may be another session answering that packet. Telegram Desktop answers in
// a couple of round trips; the margin is for slow networks.
private let ghostOtherSessionReactionInterval: Double = 10.0
// Donutgram: two such answers this close together are taken for another session.
private let ghostOtherSessionReactionChainInterval: Double = 15.0
// Donutgram: the server reporting the account offline this soon after an offline packet sent here
// may be that packet coming back rather than another session going offline.
private let ghostOwnOfflineEchoInterval: Double = 5.0

// Donutgram: whether ghost mode hides online, now and after every settings change.
func bananaGhostHidesOnlineSignal() -> Signal<Bool, NoError> {
    return Signal<Bool, NoError> { subscriber in
        subscriber.putNext(BananaPresenceSettings.shared.ghostHidesOnline)
        let observer = NotificationCenter.default.addObserver(forName: BananaPresenceSettings.didChangeNotification, object: nil, queue: nil, using: { _ in
            subscriber.putNext(BananaPresenceSettings.shared.ghostHidesOnline)
        })
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    |> distinctUntilChanged
}

private final class AccountPresenceManagerImpl {
    private let queue: Queue
    private let network: Network
    private let accountId: Int64
    private let accountPeerId: PeerId
    let isPerformingUpdate = ValuePromise<Bool>(false, ignoreRepeated: true)

    private var shouldKeepOnlinePresenceDisposable: Disposable?
    private let currentRequestDisposable = MetaDisposable()
    private let initialPresenceRequestDisposable = MetaDisposable()
    private let serverStatusRefreshDisposable = MetaDisposable()
    private var connectionStatusDisposable: Disposable?
    private var onlineTimer: SignalKitTimer?
    private var offlineFallbackTimer: SignalKitTimer?
    private var settingsObserver: NSObjectProtocol?
    private var offlineRequestObserver: NSObjectProtocol?

    private var serverOfflineObserver: NSObjectProtocol?
    private var serverStatusObserver: NSObjectProtocol?

    private enum GhostOfflineCause {
        // An action here asked for it.
        case action
        // It answers the server reporting the account online.
        case answer
        // The fallback timer or a presence change.
        case routine
    }

    private var lastPresencePolicy = (BananaPresenceSettings.shared.ghostHidesOnline, BananaPresenceSettings.shared.ghostAutomaticOffline)
    private var wasOnline: Bool = false
    // Donutgram: the last offline packet ghost mode sent, and why.
    private var lastGhostOffline: (timestamp: Double, cause: GhostOfflineCause)?
    // Donutgram: when an action here last asked for an offline packet, and whether a report of the
    // account online that came after that packet has been answered for it.
    private var lastActionOffline: (timestamp: Double, answered: Bool)?
    // Donutgram: until when (server time) another session of this account keeps it online, and when
    // the server last reported that session online.
    private var otherSessionOnlineUntil: Int32 = 0
    private var otherSessionLastReport: Double = 0.0
    // Donutgram: when the server last reported this account online.
    private var lastServerOnlineReport: Double = 0.0
    // Donutgram: the server's report of this account online waiting to be weighed.
    private var pendingServerOnline: (arrival: Double, expires: Int32)?
    // Donutgram: when the last report that looked like another session answering an offline
    // packet arrived, while no second one has followed it.
    private var lastReactionReport: Double?
    private var lastAcknowledgedPresenceOnline: Bool = false
    // Donutgram: how many reports of this account online have been recorded for the own profile, and
    // when the last one was; how many offline packets have been sent.
    private var serverOnlineRecords: Int = 0
    private var lastServerOnlineRecord: Double = 0.0
    private var offlinePacketsSent: Int = 0
    // Donutgram: whether a status request is on its way, and whether the own status is to be asked
    // for once it is answered.
    private var isStatusRequestInFlight = false
    private var pendingServerStatusRefresh = false
    // Donutgram: whether the network has been connected since the manager started.
    private var hasBeenConnected = false
    private var resolvingInitialPresence = false
    private var didResolveInitialPresence = false

    init(queue: Queue, shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network, accountId: Int64, accountPeerId: PeerId) {
        self.queue = queue
        self.network = network
        self.accountId = accountId
        self.accountPeerId = accountPeerId

        self.shouldKeepOnlinePresenceDisposable = (shouldKeepOnlinePresence
        |> distinctUntilChanged
        |> deliverOn(self.queue)).start(next: { [weak self] value in
            guard let `self` = self else {
                return
            }
            if self.wasOnline != value {
                self.wasOnline = value
                self.updatePresence(value)
                if value {
                    // Another client may have been online while the app was closed.
                    self.scheduleServerStatusRefresh()
                }
            }
        })

        self.connectionStatusDisposable = (self.network.connectionStatus
        |> map { status -> Bool in
            switch status {
            case .online, .updating:
                return true
            case .waitingForNetwork, .connecting:
                return false
            }
        }
        |> distinctUntilChanged
        |> deliverOn(self.queue)).start(next: { [weak self] isConnected in
            guard let self, isConnected else {
                return
            }
            if self.hasBeenConnected && self.wasOnline {
                // No update reports a status that changed while the connection was lost.
                self.scheduleServerStatusRefresh()
            }
            self.hasBeenConnected = true
        })

        self.settingsObserver = NotificationCenter.default.addObserver(forName: BananaPresenceSettings.didChangeNotification, object: nil, queue: nil, using: { [weak self] _ in
            guard let self else {
                return
            }
            self.queue.async { [weak self] in
                guard let self else {
                    return
                }
                let ghost = BananaPresenceSettings.shared
                let policy = (ghost.ghostHidesOnline, ghost.ghostAutomaticOffline)
                guard policy != self.lastPresencePolicy else { return }
                self.lastPresencePolicy = policy
                if !(ghost.ghostModeEnabled && ghost.ghostAutomaticOffline) {
                    self.resetOtherSessionState()
                }
                if !ghost.ghostHidesOnline {
                    // Nothing records the server's status meanwhile, so it would be stale when ghost
                    // mode hides online again.
                    ghost.setServerOnlineUntil(nil, accountId: self.accountId)
                }
                // UserDefaults changes are independent from the foreground
                // signal. Re-evaluate immediately so enabling ghost mode while
                // the app is active sends an offline packet right away.
                self.updatePresence(self.wasOnline)
            }
        })
        self.offlineRequestObserver = NotificationCenter.default.addObserver(forName: BananaPresenceSettings.requestOfflineNotification, object: BananaPresenceSettings.shared, queue: nil, using: { [weak self] notification in
            // A request without an account is for every account.
            let requestedAccountPeerId = notification.userInfo?[BananaPresenceSettings.requestOfflineAccountPeerIdKey] as? Int64
            self?.queue.async { [weak self] in
                guard let self else {
                    return
                }
                if let requestedNetwork = notification.userInfo?["network"] as? Network, requestedNetwork !== self.network { return }
                if let requestedAccountPeerId, requestedAccountPeerId != self.accountPeerId.toInt64() {
                    return
                }
                if let expires = notification.userInfo?[BananaPresenceSettings.requestOfflineServerOnlineExpiresKey] as? Int32 {
                    self.answerServerReportedOnline(expires: expires)
                } else {
                    self.requestOfflinePresence(cause: .action)
                }
            }
        })
        self.serverOfflineObserver = NotificationCenter.default.addObserver(forName: BananaPresenceSettings.serverReportedOfflineNotification, object: BananaPresenceSettings.shared, queue: nil, using: { [weak self] notification in
            let reportedAccountPeerId = notification.userInfo?[BananaPresenceSettings.requestOfflineAccountPeerIdKey] as? Int64
            let wasOnline = notification.userInfo?[BananaPresenceSettings.serverOfflineWasOnlineKey] as? Int32
            self?.queue.async { [weak self] in
                guard let self, let wasOnline, reportedAccountPeerId == self.accountPeerId.toInt64() else {
                    return
                }
                self.handleServerReportedOffline(wasOnline: wasOnline)
            }
        })
        self.serverStatusObserver = NotificationCenter.default.addObserver(forName: BananaPresenceSettings.serverReportedStatusNotification, object: BananaPresenceSettings.shared, queue: nil, using: { [weak self] notification in
            let reportedAccountPeerId = notification.userInfo?[BananaPresenceSettings.requestOfflineAccountPeerIdKey] as? Int64
            let onlineExpires = notification.userInfo?[BananaPresenceSettings.requestOfflineServerOnlineExpiresKey] as? Int32
            let offlineWasOnline = notification.userInfo?[BananaPresenceSettings.serverOfflineWasOnlineKey] as? Int32
            self?.queue.async { [weak self] in
                guard let self, reportedAccountPeerId == self.accountPeerId.toInt64() else {
                    return
                }
                self.recordServerStatus(onlineExpires: onlineExpires, offlineWasOnline: offlineWasOnline)
            }
        })
    }

    deinit {
        assert(self.queue.isCurrent())
        self.shouldKeepOnlinePresenceDisposable?.dispose()
        self.currentRequestDisposable.dispose()
        self.initialPresenceRequestDisposable.dispose()
        self.serverStatusRefreshDisposable.dispose()
        self.connectionStatusDisposable?.dispose()
        self.onlineTimer?.invalidate()
        self.offlineFallbackTimer?.invalidate()
        if let settingsObserver = self.settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        if let offlineRequestObserver = self.offlineRequestObserver {
            NotificationCenter.default.removeObserver(offlineRequestObserver)
        }
        if let serverOfflineObserver = self.serverOfflineObserver {
            NotificationCenter.default.removeObserver(serverOfflineObserver)
        }
        if let serverStatusObserver = self.serverStatusObserver {
            NotificationCenter.default.removeObserver(serverStatusObserver)
        }
    }

    private func recordAcknowledgedPresence(isOnline: Bool, timestamp: Int32, serverOnlineRecordsAtRequest: Int) {
        let ghost = BananaPresenceSettings.shared
        if isOnline || self.lastAcknowledgedPresenceOnline || ghost.lastOnlineTimestamp(accountId: self.accountId) == nil {
            ghost.setLastOnlineTimestamp(timestamp, accountId: self.accountId)
        }
        if !isOnline {
            // The packet ends an online the server reported before it was sent, whichever session
            // caused it. One reported after that may have come from another session answering it.
            if self.serverOnlineRecords == serverOnlineRecordsAtRequest, let onlineUntil = ghost.serverOnlineUntil(accountId: self.accountId) {
                ghost.setServerOnlineUntil(nil, accountId: self.accountId)
                let lastSeen = min(onlineUntil, timestamp)
                if lastSeen > (ghost.lastOnlineTimestamp(accountId: self.accountId) ?? 0) {
                    ghost.setLastOnlineTimestamp(lastSeen, accountId: self.accountId)
                }
            }
        }
        // Repeated offline requests must keep the original last-seen time.
        self.lastAcknowledgedPresenceOnline = isOnline
    }

    // Donutgram: the server reported this account's status, which is what other users see. While ghost
    // mode hides online the own profile shows it (PeerInfoData), so the online of another client is
    // shown too, not only the times this app was online.
    private func recordServerStatus(onlineExpires: Int32?, offlineWasOnline: Int32?) {
        let ghost = BananaPresenceSettings.shared
        if let offlineWasOnline {
            // An old status may be replayed, and an offline packet sent here may come back after
            // another session went online again.
            if Double(offlineWasOnline) >= self.lastServerOnlineRecord - 2.0 {
                ghost.setServerOnlineUntil(nil, accountId: self.accountId)
            }
            if offlineWasOnline > (ghost.lastOnlineTimestamp(accountId: self.accountId) ?? 0) {
                ghost.setLastOnlineTimestamp(offlineWasOnline, accountId: self.accountId)
            }
        } else if let onlineExpires {
            let now = self.network.globalTime
            // An old status replayed after a gap is no longer true.
            guard onlineExpires > Int32(now) else {
                return
            }
            self.serverOnlineRecords += 1
            self.lastServerOnlineRecord = now
            ghost.setServerOnlineUntil(onlineExpires, accountId: self.accountId)
        }
    }

    // Donutgram: asks for this account's status once the status request on its way is answered.
    // Sent alongside it, the server may answer this one first, with an online that request ends.
    private func scheduleServerStatusRefresh() {
        if self.isStatusRequestInFlight {
            self.pendingServerStatusRefresh = true
        } else {
            self.refreshServerStatus()
        }
    }

    private func statusRequestCompleted() {
        self.isStatusRequestInFlight = false
        self.isPerformingUpdate.set(false)
        if self.pendingServerStatusRefresh {
            self.pendingServerStatusRefresh = false
            self.refreshServerStatus()
        }
    }

    // Donutgram: asks the server for this account's status, so the own profile shows an online of
    // another client that no update reported here (the app was closed or disconnected meanwhile).
    private func refreshServerStatus() {
        guard BananaPresenceSettings.shared.ghostHidesOnline, !self.resolvingInitialPresence else {
            return
        }
        let offlinePacketsSent = self.offlinePacketsSent
        self.serverStatusRefreshDisposable.set((self.network.request(Api.functions.users.getUsers(id: [.inputUserSelf]), automaticFloodWait: false)
        |> `catch` { _ -> Signal<[Api.User], NoError> in
            return .single([])
        }
        |> deliverOn(self.queue)).start(next: { [weak self] users in
            guard let self, BananaPresenceSettings.shared.ghostHidesOnline else {
                return
            }
            for user in users {
                guard case let .user(data) = user, let status = data.status else { continue }
                switch status {
                case let .userStatusOnline(data):
                    // An offline packet sent after the request ends this online, even if the server
                    // has not acknowledged it yet: its acknowledgement would not end an online
                    // recorded after it was sent.
                    if self.offlinePacketsSent == offlinePacketsSent {
                        self.recordServerStatus(onlineExpires: data.expires, offlineWasOnline: nil)
                    }
                case let .userStatusOffline(data):
                    self.recordServerStatus(onlineExpires: nil, offlineWasOnline: data.wasOnline)
                default:
                    break
                }
            }
        }))
    }

    private func isOtherSessionOnline() -> Bool {
        return self.otherSessionOnlineUntil > Int32(self.network.globalTime)
    }

    private func resetOtherSessionState() {
        self.otherSessionOnlineUntil = 0
        self.pendingServerOnline = nil
        self.lastReactionReport = nil
    }

    // The server reported this account online (`updateUserStatus`). An action here usually
    // caused it, and the offline packet hides it. But another session of the account may be
    // online: Telegram Desktop, for one, sends online again as soon as it sees the account go
    // offline. Answering that one makes the two sessions flip the status between "online" and
    // "last seen just now" as fast as the requests travel. So when the server twice in a row
    // shows the account online right after an offline packet no action here asked for, the
    // account is left to the other session until its online expires or the server reports it
    // offline: while that session is online the account is shown online anyway. One such
    // report alone is not enough, since an action here nothing reports can follow the fallback
    // packet just as closely.
    private func answerServerReportedOnline(expires: Int32) {
        let now = self.network.globalTime
        // An old status replayed after a gap is no longer true.
        if expires <= Int32(now) {
            return
        }
        self.lastServerOnlineReport = now
        if let pending = self.pendingServerOnline {
            self.pendingServerOnline = (arrival: pending.arrival, expires: max(pending.expires, expires))
            return
        }
        if !self.isOtherSessionOnline() {
            if self.takeOwnActionReport(arrival: now) {
                // The online an action here caused came after that action's offline packet.
                self.lastReactionReport = nil
                self.requestOfflinePresence(cause: .answer)
                return
            }
            if !self.followsUnpromptedOffline(arrival: now) {
                // Nothing points at another session: hide it right away.
                self.lastReactionReport = nil
                self.requestOfflinePresence(cause: .answer)
                return
            }
        }
        // Wait for an action here to claim it before deciding whose it is.
        self.pendingServerOnline = (arrival: now, expires: expires)
        self.queue.after(ghostServerOnlineSettleDelay, { [weak self] in
            self?.settleServerReportedOnline()
        })
    }

    private func settleServerReportedOnline() {
        guard let pending = self.pendingServerOnline else {
            return
        }
        self.pendingServerOnline = nil
        if let lastActionOffline = self.lastActionOffline, lastActionOffline.timestamp > pending.arrival - ghostOwnActionWindow {
            // An action here may have shown the account online, so this does not count as
            // another session answering an offline packet.
            self.lastReactionReport = nil
            if lastActionOffline.timestamp >= pending.arrival {
                // The action's offline packet went out after the report and covers it.
                return
            }
            if self.takeOwnActionReport(arrival: pending.arrival) {
                // The first report after the action's offline packet is the action's own.
                self.requestOfflinePresence(cause: .answer)
                return
            }
            // A later one may come from anything, so it is weighed like any other.
        }
        if self.isOtherSessionOnline() {
            self.otherSessionOnlineUntil = max(self.otherSessionOnlineUntil, pending.expires)
            self.otherSessionLastReport = pending.arrival
            return
        }
        if let lastReactionReport = self.lastReactionReport, pending.arrival - lastReactionReport < ghostOtherSessionReactionChainInterval {
            self.lastReactionReport = nil
            self.otherSessionOnlineUntil = pending.expires
            self.otherSessionLastReport = pending.arrival
            return
        }
        self.lastReactionReport = pending.arrival
        self.requestOfflinePresence(cause: .answer)
    }

    // Whether an action here sent its offline packet shortly before `arrival` and no report of the
    // account online has been answered for it yet; marks it answered.
    private func takeOwnActionReport(arrival: Double) -> Bool {
        guard let lastActionOffline = self.lastActionOffline, !lastActionOffline.answered, lastActionOffline.timestamp <= arrival, lastActionOffline.timestamp > arrival - ghostOwnActionWindow else {
            return false
        }
        self.lastActionOffline = (timestamp: lastActionOffline.timestamp, answered: true)
        return true
    }

    private func followsUnpromptedOffline(arrival: Double) -> Bool {
        guard let lastGhostOffline = self.lastGhostOffline, lastGhostOffline.cause != .action else {
            return false
        }
        return arrival - lastGhostOffline.timestamp < ghostOtherSessionReactionInterval
    }

    // The server reported this account offline. While another session was taken to keep it
    // online, that session has gone offline, so the account is ghost mode's again.
    private func handleServerReportedOffline(wasOnline: Int32) {
        guard self.isOtherSessionOnline() else {
            return
        }
        // The offline packet sent here may come back, and an old status may be replayed.
        if let lastGhostOffline = self.lastGhostOffline, self.network.globalTime - lastGhostOffline.timestamp < ghostOwnOfflineEchoInterval {
            return
        }
        if Double(wasOnline) < self.otherSessionLastReport - 2.0 {
            return
        }
        self.resetOtherSessionState()
    }

    private func requestOfflinePresence(cause: GhostOfflineCause) {
        guard !self.resolvingInitialPresence else { return }
        // The request may have been queued before ghost mode was turned off.
        let ghost = BananaPresenceSettings.shared
        guard ghost.ghostModeEnabled && ghost.ghostAutomaticOffline else { return }
        // While another session keeps the account online the fallback packet would only make it
        // flip. Actions and the reports they caused are still answered: if the other session is
        // gone by now, the account would stay online otherwise.
        if cause == .routine && self.isOtherSessionOnline() {
            return
        }
        let now = self.network.globalTime
        self.lastGhostOffline = (timestamp: now, cause: cause)
        if cause == .action {
            self.lastActionOffline = (timestamp: now, answered: false)
        }
        if self.isOtherSessionOnline() {
            // A session that keeps the account online answers every offline packet. One that
            // stays silent is gone, even if it never sent its own offline (killed, asleep, cut
            // off), so the account is ghost mode's again.
            self.queue.after(ghostOtherSessionReactionInterval, { [weak self] in
                guard let self, self.isOtherSessionOnline(), self.lastServerOnlineReport < now else {
                    return
                }
                self.resetOtherSessionState()
            })
        }
        let timestamp = Int32(self.network.globalTime)
        let serverOnlineRecords = self.serverOnlineRecords
        self.offlinePacketsSent += 1
        let request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        self.isPerformingUpdate.set(true)
        self.isStatusRequestInFlight = true
        self.currentRequestDisposable.set((request
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }
        |> deliverOn(self.queue)).start(next: { [weak self] result in
            if case .boolTrue = result {
                self?.recordAcknowledgedPresence(isOnline: false, timestamp: timestamp, serverOnlineRecordsAtRequest: serverOnlineRecords)
            }
        }, completed: { [weak self] in
            self?.statusRequestCompleted()
        }))
    }

    private func updateOfflineFallbackTimer(isActive: Bool) {
        if isActive {
            if self.offlineFallbackTimer == nil {
                let timer = SignalKitTimer(timeout: ghostOfflineFallbackInterval, repeat: true, completion: { [weak self] in
                    self?.requestOfflinePresence(cause: .routine)
                }, queue: self.queue)
                self.offlineFallbackTimer = timer
                timer.start()
            }
        } else {
            self.offlineFallbackTimer?.invalidate()
            self.offlineFallbackTimer = nil
        }
    }

    func reassertPresence() { self.updatePresence(self.wasOnline) }

    private func updatePresence(_ isOnline: Bool) {
        let ghost = BananaPresenceSettings.shared
        let effectiveOnline = isOnline && !ghost.ghostHidesOnline
        if !effectiveOnline && ghost.ghostHidesOnline && !self.didResolveInitialPresence && ghost.lastOnlineTimestamp(accountId: self.accountId) == nil {
            if !self.resolvingInitialPresence {
                self.resolvingInitialPresence = true
                self.onlineTimer?.invalidate()
                self.onlineTimer = nil
                // Fetch the real self status before the first offline packet.
                // Postbox deliberately replaces self presence with "online".
                // Bound the lookup so an unavailable server cannot stall it.
                self.initialPresenceRequestDisposable.set((self.network.request(Api.functions.users.getUsers(id: [.inputUserSelf]), automaticFloodWait: false)
                |> `catch` { _ -> Signal<[Api.User], NoError> in
                    return .single([])
                }
                |> timeout(2.0, queue: self.queue, alternate: .single([]))
                |> deliverOn(self.queue)).start(next: { [weak self] users in
                    guard let self, ghost.lastOnlineTimestamp(accountId: self.accountId) == nil else { return }
                    for user in users {
                        guard case let .user(data) = user, let status = data.status else { continue }
                        switch status {
                        case let .userStatusOffline(data):
                            ghost.setLastOnlineTimestamp(data.wasOnline, accountId: self.accountId)
                        case let .userStatusOnline(data):
                            self.lastAcknowledgedPresenceOnline = true
                            self.recordServerStatus(onlineExpires: data.expires, offlineWasOnline: nil)
                        default:
                            break
                        }
                    }
                }, completed: { [weak self] in
                    guard let self else { return }
                    self.resolvingInitialPresence = false
                    self.didResolveInitialPresence = true
                    self.updatePresence(self.wasOnline)
                }))
            }
            return
        } else if self.resolvingInitialPresence {
            self.initialPresenceRequestDisposable.set(nil)
            self.resolvingInitialPresence = false
            self.didResolveInitialPresence = true
        }
        let timestamp = Int32(self.network.globalTime)
        let serverOnlineRecords = self.serverOnlineRecords
        let request: Signal<Api.Bool, MTRpcError>
        if effectiveOnline {
            self.updateOfflineFallbackTimer(isActive: false)
            let timer = SignalKitTimer(timeout: 30.0, repeat: false, completion: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.updatePresence(true)
            }, queue: self.queue)
            self.onlineTimer = timer
            timer.start()
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolFalse))
        } else {
            self.onlineTimer?.invalidate()
            self.onlineTimer = nil
            // `isOnline` is true while the app is in front: only then can the user act.
            self.updateOfflineFallbackTimer(isActive: isOnline && ghost.ghostModeEnabled && ghost.ghostAutomaticOffline)
            if ghost.ghostHidesOnline {
                self.lastGhostOffline = (timestamp: self.network.globalTime, cause: GhostOfflineCause.routine)
            }
            self.offlinePacketsSent += 1
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        }
        self.isPerformingUpdate.set(true)
        self.isStatusRequestInFlight = true
        self.currentRequestDisposable.set((request
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }
        |> deliverOn(self.queue)).start(next: { [weak self] result in
            if case .boolTrue = result {
                self?.recordAcknowledgedPresence(isOnline: effectiveOnline, timestamp: timestamp, serverOnlineRecordsAtRequest: serverOnlineRecords)
            }
        }, completed: { [weak self] in
            self?.statusRequestCompleted()
        }))
    }
}

final class AccountPresenceManager {
    private let queue = Queue()
    private let impl: QueueLocalObject<AccountPresenceManagerImpl>

    init(shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network, accountId: Int64, accountPeerId: PeerId) {
        let queue = self.queue
        self.impl = QueueLocalObject(queue: self.queue, generate: {
            return AccountPresenceManagerImpl(queue: queue, shouldKeepOnlinePresence: shouldKeepOnlinePresence, network: network, accountId: accountId, accountPeerId: accountPeerId)
        })
    }

    func reassertPresence() { self.impl.with { $0.reassertPresence() } }

    func isPerformingUpdate() -> Signal<Bool, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                disposable.set(impl.isPerformingUpdate.get().start(next: { value in
                    subscriber.putNext(value)
                }))
            }
            return disposable
        }
    }
}
