final class TestNetwork { var globalTime: Double = 100 }
final class TestQueue {
    var pending: [() -> Void] = []
    func after(_ delay: Double, _ action: @escaping () -> Void) { pending.append(action) }
}
final class Presence {
    enum GhostOfflineCause { case action, answer, routine }
    let network = TestNetwork()
    let queue = TestQueue()
    var otherSessionOnlineUntil: Int32 = 0
    var otherSessionLastReport: Double = 0
    var lastServerOnlineReport: Double = 0
    var pendingServerOnline: (arrival: Double, expires: Int32)?
    var lastReactionReport: Double?
    var lastGhostOffline: (timestamp: Double, cause: GhostOfflineCause)?
    var lastActionOffline: (timestamp: Double, answered: Bool)?
    var requests = 0
    func requestOfflinePresence(cause: GhostOfflineCause) {
        requests += 1
        lastGhostOffline = (network.globalTime, cause)
        if cause == .action { lastActionOffline = (network.globalTime, false) }
    }
    // PRODUCTION METHODS
}
let local = Presence()
local.answerServerReportedOnline(expires: 99)
precondition(local.requests == 0, "ignore expired server updates")
local.requestOfflinePresence(cause: .action)
local.network.globalTime = 101
local.answerServerReportedOnline(expires: 200)
precondition(local.requests == 2 && local.lastReactionReport == nil, "answer own action immediately")

let desktop = Presence()
desktop.requestOfflinePresence(cause: .routine)
desktop.network.globalTime = 101
desktop.answerServerReportedOnline(expires: 200)
precondition(desktop.requests == 1 && desktop.pendingServerOnline != nil)
desktop.network.globalTime = 104
desktop.settleServerReportedOnline()
precondition(desktop.requests == 2 && desktop.otherSessionOnlineUntil == 0)
desktop.network.globalTime = 105
desktop.answerServerReportedOnline(expires: 210)
desktop.network.globalTime = 108
desktop.settleServerReportedOnline()
precondition(desktop.requests == 2 && desktop.otherSessionOnlineUntil == 210, "two keepalives establish other session; stop flipping status")
desktop.network.globalTime = 110
desktop.answerServerReportedOnline(expires: 220)
desktop.network.globalTime = 113
desktop.settleServerReportedOnline()
precondition(desktop.requests == 2 && desktop.otherSessionOnlineUntil == 220)
desktop.network.globalTime = 120
desktop.handleServerReportedOffline(wasOnline: 119)
precondition(desktop.otherSessionOnlineUntil == 0 && desktop.pendingServerOnline == nil, "other session offline releases the status")
