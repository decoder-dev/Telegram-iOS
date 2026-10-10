import Foundation
#if canImport(FoundationModels)
@_weakLinked import FoundationModels
#endif

enum ForkOnDeviceAIError: Error {
    case unavailable
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
    
    /// Summarises `text` in the language it is written in. `completion` runs on an arbitrary queue.
    static func summarize(_ text: String, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            Task {
                do {
                    let session = LanguageModelSession(instructions: "You summarise chat messages. Reply with at most three short sentences, in the same language as the message. Output only the summary, with no introduction and no comments.")
                    let response = try await session.respond(to: text)
                    completion(.success(response.content))
                } catch {
                    completion(.failure(error))
                }
            }
            return
        }
        #endif
        completion(.failure(ForkOnDeviceAIError.unavailable))
    }
}
