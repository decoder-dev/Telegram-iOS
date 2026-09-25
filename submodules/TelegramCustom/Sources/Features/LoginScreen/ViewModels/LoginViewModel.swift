import Foundation
import Combine

@available(iOS 14.0, *)
class LoginViewModel: ObservableObject {
    /// Handle quick access login (placeholder for future SDK integration)
    func handleQuickAccess() {
        // TODO: Integrate SDK and server token logic
        // Current implementation: log only, no UI response
        #if DEBUG
        print("[LoginViewModel] Quick access feature pending")
        #endif
    }
}
