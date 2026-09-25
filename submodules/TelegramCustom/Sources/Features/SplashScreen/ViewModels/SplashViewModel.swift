import Foundation
import Combine
import TelegramCustomCore

@available(iOS 14.0, *)
class SplashViewModel: ObservableObject {
    @Published var countdown: Int = AppConstants.splashCountdownSeconds
    private var timer: Timer?

    func startCountdown(completion: @escaping () -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.countdown > 0 {
                self.countdown -= 1
            } else {
                self.cancelTimer()
                completion()
            }
        }
    }

    func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        cancelTimer()
    }
}
