import Foundation
import UIKit
import SwiftSignalKit

public typealias ListViewTransaction = (@escaping () -> Void) -> Void

/// Serialises list transactions: one runs at a time, the next starts when the previous one reports
/// completion.
///
/// The queue is drained by a loop, not by recursion, and that is the whole point of the shape below.
/// A transaction that completes synchronously — which is the common case, since most list updates
/// finish inside the same call — used to re-enter `endTransaction` and start the next transaction
/// from inside the previous one's stack frame. The hop that was supposed to prevent that,
/// `Queue.mainQueue().async`, does not hop: `Queue` is constructed for the main queue with
/// `specialIsMainQueue: true`, so `async` sees `isCurrent()` and runs the block inline.
///
/// The cost was one stack frame set per queued transaction, and a tester's launch crash was exactly
/// that: SIGSEGV in the stack guard page, with the ten frames
///
///   `ListViewImpl.transaction` → `deleteAndInsertItemsTransaction` → completion thunks →
///   `addTransaction`'s completion → `Queue.async` → `endTransaction`'s block →
///   `ListViewImpl.transaction`
///
/// repeating to the top of the captured backtrace. Draining in a loop makes the depth constant
/// regardless of how many transactions are queued.
public final class ListViewTransactionQueue {
    private var transactions: [ListViewTransaction] = []
    public final var transactionCompleted: () -> Void = { }

    /// True while `drain` is walking the queue. A transaction that completes synchronously re-enters
    /// through `endTransaction`; the flag turns that re-entry into another pass of the loop that is
    /// already running instead of another stack frame.
    private var isDraining = false
    private var needsAnotherPass = false
    
    public init() {
    }
    
    public func addTransaction(_ transaction: @escaping ListViewTransaction) {
        precondition(Thread.isMainThread)
        let beginTransaction = self.transactions.count == 0
        self.transactions.append(transaction)
        
        if beginTransaction {
            self.drain()
        } else {
            assert(true)
        }
    }

    private func drain() {
        precondition(Thread.isMainThread)

        if self.isDraining {
            self.needsAnotherPass = true
            return
        }
        self.isDraining = true
        defer {
            self.isDraining = false
        }

        repeat {
            self.needsAnotherPass = false
            guard let transaction = self.transactions.first else {
                break
            }
            // A transaction may complete on this call (synchronous path, handled by the loop) or
            // later, from an animation or an async layout (asynchronous path, which leaves the loop
            // and starts a fresh drain from `endTransaction`).
            transaction({ [weak self] in
                precondition(Thread.isMainThread)

                if Thread.isMainThread {
                    if let strongSelf = self {
                        strongSelf.endTransaction()
                    }
                } else {
                    Queue.mainQueue().async {
                        if let strongSelf = self {
                            strongSelf.endTransaction()
                        }
                    }
                }
            })
        } while self.needsAnotherPass
    }
    
    private func endTransaction() {
        precondition(Thread.isMainThread)

        self.transactionCompleted()
        if !self.transactions.isEmpty {
            let _ = self.transactions.removeFirst()
        }

        if !self.transactions.isEmpty {
            self.drain()
        }
    }
}
