import Foundation

struct RoundVideoRecordingCountdown {
    private var deadline: Double?

    var isRunning: Bool { self.deadline != nil }

    mutating func start(at timestamp: Double) {
        self.deadline = timestamp + 3.0
    }

    mutating func cancel() {
        self.deadline = nil
    }

    func remaining(at timestamp: Double) -> Int? {
        guard let deadline = self.deadline else { return nil }
        return max(0, min(3, Int(ceil(deadline - timestamp))))
    }
}
