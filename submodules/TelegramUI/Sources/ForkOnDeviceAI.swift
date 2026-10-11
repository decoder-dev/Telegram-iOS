import Foundation
import SwiftSignalKit
#if canImport(FoundationModels)
@_weakLinked import FoundationModels
#endif

enum ForkOnDeviceAIError: Error, Equatable {
    case unavailable
    case busy
}

/// Text generation by the system language model that runs on the device (Apple Foundation Models). Nothing leaves the
/// phone. The framework exists from iOS 26 and only on hardware with Apple Intelligence switched on, so every entry
/// point answers "not available" instead of failing, and the framework is linked weakly.
enum ForkOnDeviceAI {
    /// Shortest message the summary entry is offered for; a shorter text is quicker to read than to summarise.
    static let minimumSummarizedLength = 280
    
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
        }
        #endif
        return false
    }
    
    private static let inProgress = Atomic<Bool>(value: false)

    /// A single model request at a time. Disposing cancels generation and suppresses its result.
    static func summarize(_ text: String) -> Signal<String, Error> {
        return Signal { subscriber in
            guard !self.inProgress.swap(true) else {
                subscriber.putError(ForkOnDeviceAIError.busy)
                return EmptyDisposable
            }
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *), self.isAvailable {
                let cancelled = Atomic<Bool>(value: false)
                let task = Task {
                    defer { let _ = self.inProgress.swap(false) }
                    do {
                        try Task.checkCancellation()
                        let session = LanguageModelSession(instructions: "You summarise chat messages. Reply with at most three short sentences, in the same language as the message. Output only the summary, with no introduction and no comments.")
                        let response = try await session.respond(to: text)
                        try Task.checkCancellation()
                        guard !cancelled.with({ $0 }) else { return }
                        subscriber.putNext(response.content)
                        subscriber.putCompletion()
                    } catch {
                        if !cancelled.with({ $0 }) {
                            subscriber.putError(error)
                        }
                    }
                }
                return ActionDisposable {
                    let _ = cancelled.swap(true)
                    task.cancel()
                }
            }
            #endif
            let _ = self.inProgress.swap(false)
            subscriber.putError(ForkOnDeviceAIError.unavailable)
            return EmptyDisposable
        }
    }
}
