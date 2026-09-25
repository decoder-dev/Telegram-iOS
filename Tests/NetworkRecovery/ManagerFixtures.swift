import Foundation

enum WebProxyLog { static func log(_ text: String) {} }
enum WebProxyHttpCarrierError: Error { case sessionCreationFailed, carrierClosed }
struct WebProxyBridgeCapability {
    static func derive(hostname: String, secret: Data) -> Self? { Self() }
}
struct NWPath {
    enum Status { case satisfied, unsatisfied }
    struct Interface { var type = "wifi" }
    var status = Status.satisfied
    var availableInterfaces: [Interface] = []
}
final class NWPathMonitor {
    var pathUpdateHandler: ((NWPath) -> Void)?
    func start(queue: DispatchQueue) {}
    func cancel() {}
}
public final class WebProxySidecar {
    public struct Endpoint { var host: String; var port: UInt16 }
    public struct SocksBridgeEndpoint {}
    var reconnectCount = 0
    var stopCount = 0
    var pending: ((Result<Void, Error>) -> Void)?
    var failure: (() -> Void)?
    func socksBridgeEndpoint() -> SocksBridgeEndpoint? { nil }
    func sendKeepalivePing() {}
    func secondsSinceLastActivity() -> Double { 100 }
    func start(hostname: String, secret: Data, bridgeCapability: WebProxyBridgeCapability,
               completion: @escaping (Result<Endpoint, Error>) -> Void) {}
    func setFailureHandler(_ handler: @escaping () -> Void) { failure = handler }
    func stop() { stopCount += 1 }
    func reconnectTransport(completion: @escaping (Result<Void, Error>) -> Void) {
        reconnectCount += 1
        pending = completion
    }
    func finish(_ result: Result<Void, Error>) {
        let callback = pending
        pending = nil
        callback?(result)
    }
}

extension WebProxyManager {
    static func testInstance() -> WebProxyManager { WebProxyManager() }
    func installForTest(_ sidecar: WebProxySidecar, _ profile: WebProxyConfiguration) {
        self.desiredConfiguration = profile
        self.sidecar = sidecar
        self.configuration = profile
        self.endpoint = LoopbackEndpoint(host: "127.0.0.1", port: 1234)
        self.sidecarReadySince = ProcessInfo.processInfo.systemUptime
    }
    func resumeForTest(_ sidecar: WebProxySidecar, _ profile: WebProxyConfiguration) {
        self.performInPlaceCarrierResume(sidecar: sidecar, configuration: profile)
    }
    func failureForTest(_ sidecar: WebProxySidecar) {
        self.handleSidecarFailure(expectedSidecar: sidecar)
    }
    var failuresForTest: Int { self.consecutiveFailureCount }
    func pendingStartForTest(_ profile: WebProxyConfiguration) {
        self.desiredConfiguration = profile
        self.startingConfiguration = profile
        self.startingSince = ProcessInfo.processInfo.systemUptime
    }
    var startGenerationForTest: UInt64 { self.startGeneration }
}

let profile = WebProxyConfiguration(hostname: "test.example", secret: Data([1]))
let manager = WebProxyManager.testInstance()
let sidecar = WebProxySidecar()
manager.installForTest(sidecar, profile)
var resumedEvents = 0
var stoppedEvents = 0
let token = manager.addSidecarEventHandler {
    if $0 == .carrierResumedInPlace { resumedEvents += 1 }
    if $0 == .stopped { stoppedEvents += 1 }
}
for _ in 0..<100 { manager.resumeForTest(sidecar, profile) }
precondition(sidecar.reconnectCount == 1, "one reconnect per carrier")
sidecar.finish(.success(()))
RunLoop.main.run(until: Date().addingTimeInterval(0.02))
precondition(resumedEvents == 1)
manager.resumeForTest(sidecar, profile)
sidecar.finish(.failure(WebProxyHttpCarrierError.carrierClosed))
manager.failureForTest(sidecar)
RunLoop.main.run(until: Date().addingTimeInterval(0.02))
precondition(manager.failuresForTest == 1 && sidecar.stopCount == 1 && stoppedEvents == 1)
precondition(manager.activeLoopbackEndpoint == nil)
manager.configure(activeWebProxy: nil)

// Disabling a profile while its reconnect is in flight must not resurrect it.
let old = WebProxySidecar()
manager.installForTest(old, profile)
manager.resumeForTest(old, profile)
manager.configure(activeWebProxy: nil)
old.finish(.failure(WebProxyHttpCarrierError.carrierClosed))
precondition(manager.activeLoopbackEndpoint == nil && manager.failuresForTest == 0)

// A callback from a superseded carrier must not stop the replacement, even for the same URL.
manager.installForTest(old, profile)
manager.resumeForTest(old, profile)
let replacement = WebProxySidecar()
manager.installForTest(replacement, profile)
old.finish(.failure(WebProxyHttpCarrierError.carrierClosed))
manager.failureForTest(old)
precondition(replacement.stopCount == 0 && manager.activeLoopbackEndpoint != nil)
manager.configure(activeWebProxy: nil)
manager.removeSidecarEventHandler(token)
let pendingManager = WebProxyManager.testInstance()
pendingManager.pendingStartForTest(profile)
let generation = pendingManager.startGenerationForTest
for _ in 0..<100 { pendingManager.applicationDidBecomeActive() }
precondition(pendingManager.startGenerationForTest == generation, "foreground must join pending bootstrap")
pendingManager.configure(activeWebProxy: nil)
print("WEB reconnect coalescing, duplicate failure, disabled profile and stale carrier: passed")
