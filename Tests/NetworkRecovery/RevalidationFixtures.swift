import Foundation

private enum MediaReferenceRevalidationKey: Hashable { case message }

private final class Queue {
    private var pending: [() -> Void] = []

    func async(_ action: () -> Void) { action() }

    func justDispatch(_ action: @escaping () -> Void) { self.pending.append(action) }

    func drain() {
        while !self.pending.isEmpty {
            self.pending.removeFirst()()
        }
    }
}

private protocol Disposable {
    func dispose()
}

private final class ActionDisposable: Disposable {
    private var action: (() -> Void)?

    init(_ action: @escaping () -> Void) { self.action = action }

    func dispose() {
        let action = self.action
        self.action = nil
        action?()
    }
}

private final class MetaDisposable: Disposable {
    private var disposable: Disposable?

    func set(_ disposable: Disposable) { self.disposable = disposable }

    func dispose() {
        let disposable = self.disposable
        self.disposable = nil
        disposable?.dispose()
    }
}

// PRODUCTION_REVALIDATION

private func verifyRevalidation() {
    let queue = Queue()
    var impl: MediaReferenceRevalidationContextImpl? = MediaReferenceRevalidationContextImpl(queue: queue)
    var requests = 0
    var releases = 0
    var fail: ((RevalidateMediaReferenceError) -> Void)?
    var results: [Int] = []
    let deferred: MediaReferenceRevalidationRequest = { _, error, _ in
        requests += 1
        fail = error
        return ActionDisposable { releases += 1 }
    }
    let synchronous: MediaReferenceRevalidationRequest = { next, _, completed in
        requests += 1
        next(42)
        completed()
        return ActionDisposable { releases += 1 }
    }
    let empty: MediaReferenceRevalidationRequest = { _, _, completed in
        requests += 1
        completed()
        return ActionDisposable { releases += 1 }
    }
    let record: (MediaReferenceRevalidationResult) -> Void = { result in
        switch result {
        case let .success(value): results.append(value as! Int)
        case .failure: results.append(-1)
        }
    }

    _ = impl?.genericItem(key: .message, background: false, request: deferred, record)
    _ = impl?.genericItem(key: .message, background: false, request: deferred, record)
    precondition(requests == 1)
    fail?(.generic)
    queue.drain()
    precondition(results == [-1, -1] && releases == 1)

    _ = impl?.genericItem(key: .message, background: false, request: synchronous, record)
    _ = impl?.genericItem(key: .message, background: true, request: empty, record)
    queue.drain()
    precondition(results == [-1, -1, 42, -1] && requests == 3 && releases == 3)

    let cancelled = impl?.genericItem(key: .message, background: false, request: deferred, record)
    let remaining = impl?.genericItem(key: .message, background: false, request: deferred, record)
    cancelled?.dispose()
    precondition(releases == 3)
    remaining?.dispose()
    precondition(releases == 4)
    let staleFailure = fail
    _ = impl?.genericItem(key: .message, background: false, request: deferred, record)
    staleFailure?(.generic)
    queue.drain()
    precondition(results.count == 4 && requests == 5 && releases == 4)
    fail?(.generic)
    queue.drain()
    precondition(results == [-1, -1, 42, -1, -1] && releases == 5)

    _ = impl?.genericItem(key: .message, background: false, request: deferred, record)
    impl = nil
    precondition(releases == 6, "Callbacks must not keep a discarded context alive")
    fail?(.generic)
    queue.drain()
    precondition(results.count == 5)
}

verifyRevalidation()
print("Media reference refresh terminal events, coalescing, cancellation and lifetimes: passed")
