import Foundation
import Postbox
import SwiftSignalKit

private final class SynchronizePeerReadStatesContextImpl {
    private final class Operation {
        let operation: PeerReadStateSynchronizationOperation
        let disposable: Disposable
        
        init(
            operation: PeerReadStateSynchronizationOperation,
            disposable: Disposable
        ) {
            self.operation = operation
            self.disposable = disposable
        }
        
        deinit {
            self.disposable.dispose()
        }
    }
    
    private let queue: Queue
    private let network: Network
    private let postbox: Postbox
    private let stateManager: AccountStateManager
    
    private var disposable: Disposable?
    
    private var currentState: [PeerId : PeerReadStateSynchronizationOperation] = [:]
    private var activeOperations: [PeerId: Operation] = [:]
    private var pendingOperations: [PeerId: PeerReadStateSynchronizationOperation] = [:]

    /// Consecutive failures per peer, and the timer that owns each peer while it waits.
    ///
    /// A failed operation used to be retried the instant it failed: the error path dropped the
    /// active operation and called `update()`, which found the same operation still sitting in
    /// `currentState` — it is only cleared once the sync succeeds — and started it again. Against
    /// a peer the server keeps rejecting that is a spin at the speed of the network. In one
    /// tester's log a single peer ran 191 retries with a median gap of 0.24 s, four requests a
    /// second going nowhere, on the radio, for as long as the failure lasted.
    private var failureCounts: [PeerId: Int] = [:]
    private var retryDisposables: [PeerId: MetaDisposable] = [:]
    private static let minimumRetryInterval: Double = 1.0
    private static let maximumRetryInterval: Double = 60.0
    
    init(queue: Queue, network: Network, postbox: Postbox, stateManager: AccountStateManager) {
        self.queue = queue
        self.network = network
        self.postbox = postbox
        self.stateManager = stateManager
        
        self.disposable = (postbox.synchronizePeerReadStatesView()
        |> deliverOn(self.queue)).start(next: { [weak self] view in
            guard let strongSelf = self else {
                return
            }
            strongSelf.currentState = view.operations
            strongSelf.update()
        })
    }
    
    deinit {
        self.disposable?.dispose()
        for (_, disposable) in self.retryDisposables {
            disposable.dispose()
        }
    }
    
    func dispose() {
    }
    
    /// Holds the peer out of `update()` for an exponentially growing window, then lets it back in.
    private func scheduleRetry(peerId: PeerId, operation: PeerReadStateSynchronizationOperation) {
        let failureCount = (self.failureCounts[peerId] ?? 0) + 1
        self.failureCounts[peerId] = failureCount
        let delay = min(
            SynchronizePeerReadStatesContextImpl.maximumRetryInterval,
            SynchronizePeerReadStatesContextImpl.minimumRetryInterval * pow(2.0, Double(failureCount - 1))
        )
        Logger.shared.log("SynchronizePeerReadStates", "\(peerId): operation retry \(operation) in \(delay)s (failure \(failureCount))")

        let disposable = MetaDisposable()
        self.retryDisposables[peerId] = disposable
        disposable.set((Signal<Never, NoError>.complete()
        |> delay(delay, queue: self.queue)).start(completed: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.retryDisposables.removeValue(forKey: peerId)
            strongSelf.update()
        }))
    }

    private func update() {
        let peerIds = Set(self.currentState.keys).union(Set(self.pendingOperations.keys))
        
        for peerId in peerIds {
            if self.retryDisposables[peerId] != nil {
                // A backoff timer owns this peer and will call back here when it expires. Whatever
                // the newest operation is by then, `currentState` will still be holding it.
                continue
            }
            var maybeOperation: PeerReadStateSynchronizationOperation?
            if let operation = self.currentState[peerId] {
                maybeOperation = operation
                Logger.shared.log("SynchronizePeerReadStates", "\(peerId): take new operation \(operation)")
            } else if let operation = self.pendingOperations[peerId] {
                maybeOperation = operation
                self.pendingOperations.removeValue(forKey: peerId)
                Logger.shared.log("SynchronizePeerReadStates", "\(peerId): retrieve pending operation \(operation)")
            }
            
            if let operation = maybeOperation {
                if let current = self.activeOperations[peerId] {
                    if current.operation != operation {
                        Logger.shared.log("SynchronizePeerReadStates", "\(peerId): store pending operation \(operation) (active is \(current.operation))")
                        self.pendingOperations[peerId] = operation
                    } else {
                        Logger.shared.log("SynchronizePeerReadStates", "\(peerId): do nothing, no change in \(operation)")
                    }
                } else {
                    Logger.shared.log("SynchronizePeerReadStates", "\(peerId): begin operation \(operation)")
                    let operationDisposable = MetaDisposable()
                    let activeOperation = Operation(
                        operation: operation,
                        disposable: operationDisposable
                    )
                    self.activeOperations[peerId] = activeOperation
                    let signal: Signal<Never, PeerReadStateValidationError>
                    switch operation {
                    case .Validate:
                        signal = synchronizePeerReadState(network: self.network, postbox: self.postbox, stateManager: self.stateManager, peerId: peerId, push: false, validate: true)
                        |> ignoreValues
                    case let .Push(_, thenSync):
                        signal = synchronizePeerReadState(network: self.network, postbox: self.postbox, stateManager: stateManager, peerId: peerId, push: true, validate: thenSync)
                        |> ignoreValues
                    }
                    operationDisposable.set((signal
                    |> deliverOn(self.queue)).start(error: { [weak self, weak activeOperation] _ in
                        guard let strongSelf = self else {
                            return
                        }
                        if let activeOperation = activeOperation {
                            if let current = strongSelf.activeOperations[peerId], current === activeOperation {
                                strongSelf.activeOperations.removeValue(forKey: peerId)
                                strongSelf.scheduleRetry(peerId: peerId, operation: operation)
                            }
                        }
                    }, completed: { [weak self, weak activeOperation] in
                        guard let strongSelf = self else {
                            return
                        }
                        if let activeOperation = activeOperation {
                            if let current = strongSelf.activeOperations[peerId], current === activeOperation {
                                Logger.shared.log("SynchronizePeerReadStates", "\(peerId): operation completed \(operation)")
                                strongSelf.activeOperations.removeValue(forKey: peerId)
                                strongSelf.failureCounts.removeValue(forKey: peerId)
                                strongSelf.update()
                            }
                        }
                    }))
                }
            }
        }
    }
}

private final class SynchronizePeerReadStatesStatesContext {
    private let queue: Queue
    private let impl: QueueLocalObject<SynchronizePeerReadStatesContextImpl>
    
    init(network: Network, postbox: Postbox, stateManager: AccountStateManager) {
        self.queue = Queue()
        let queue = self.queue
        self.impl = QueueLocalObject(queue: queue, generate: {
            return SynchronizePeerReadStatesContextImpl(queue: queue, network: network, postbox: postbox, stateManager: stateManager)
        })
    }
    
    func dispose() {
        self.impl.with { impl in
            impl.dispose()
        }
    }
}

func managedSynchronizePeerReadStates(network: Network, postbox: Postbox, stateManager: AccountStateManager) -> Signal<Void, NoError> {
    return Signal { _ in
        let context = SynchronizePeerReadStatesStatesContext(network: network, postbox: postbox, stateManager: stateManager)
        
        return ActionDisposable {
            context.dispose()
        }
    }
}
