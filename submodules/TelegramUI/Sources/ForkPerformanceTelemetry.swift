import Foundation
import UIKit
import MetricKit
import TelegramCore

/// Thermal and CPU telemetry.
///
/// The app previously had no way to answer "what is hot" from inside itself: two `OSSignposter`
/// instances in the entire tree, no MetricKit subscriber, and no thermal-state observer. Every
/// diagnosis of a heat report therefore required Instruments attached to a device, which is not
/// something a user can provide. This records the two signals that need no tooling to collect.
///
/// Nothing here throttles or changes behaviour — it only observes. Deciding what work to shed
/// when the device is hot requires knowing what that work costs, which is what this is for.
public enum ForkPerformanceTelemetry {
    private static var installed = false

    /// Latest observed thermal state. Readable synchronously so a future throttling decision does
    /// not have to hop a queue on a layout path. Updated on the main queue only.
    public static private(set) var thermalState: ProcessInfo.ThermalState = .nominal

    /// Whether the system considers the device thermally stressed. `.serious` is the first level
    /// at which iOS itself starts reducing performance, so it is the right threshold for the app
    /// to start shedding optional work rather than waiting for `.critical`.
    public static var isThermallyStressed: Bool {
        switch self.thermalState {
        case .serious, .critical:
            return true
        default:
            return false
        }
    }

    private static var metricSubscriber: ForkMetricSubscriber?

    /// Call once, at launch. Safe to call again — later calls do nothing.
    public static func install() {
        guard !self.installed else {
            return
        }
        self.installed = true

        self.thermalState = ProcessInfo.processInfo.thermalState
        Logger.shared.log("Perf", "thermal state at launch: \(ForkPerformanceTelemetry.describe(self.thermalState))")

        // Process-lifetime observer, deliberately never removed.
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main,
            using: { _ in
                let updated = ProcessInfo.processInfo.thermalState
                guard updated != self.thermalState else {
                    return
                }
                let previous = self.thermalState
                self.thermalState = updated
                Logger.shared.log("Perf", "thermal state \(ForkPerformanceTelemetry.describe(previous)) -> \(ForkPerformanceTelemetry.describe(updated))")
            }
        )

        // MetricKit delivers at most one payload per day, aggregated by the system, and only on
        // a real device — it is silent in the simulator. This is the only signal here that comes
        // back from users rather than from a developer's desk.
        let subscriber = ForkMetricSubscriber()
        self.metricSubscriber = subscriber
        MXMetricManager.shared.add(subscriber)
    }

    private static func describe(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown(\(state.rawValue))"
        }
    }
}

private final class ForkMetricSubscriber: NSObject, MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            // A one-line summary of the scalar metrics, so the interesting numbers are greppable
            // without parsing anything. Histograms are deliberately left out — they do not
            // interpolate into anything readable and the full JSON below carries them.
            var parts: [String] = []
            if let cpu = payload.cpuMetrics {
                parts.append("cpuTime=\(cpu.cumulativeCPUTime)")
            }
            if let disk = payload.diskIOMetrics {
                parts.append("logicalWrites=\(disk.cumulativeLogicalWrites)")
            }
            // Exit metrics arrived in iOS 14; the app deploys to 13.
            if #available(iOS 14.0, *) {
                if let exit = payload.applicationExitMetrics {
                    let background = exit.backgroundExitData
                    parts.append("bgExit.cpuLimit=\(background.cumulativeCPUResourceLimitExitCount)")
                    parts.append("bgExit.memLimit=\(background.cumulativeMemoryResourceLimitExitCount)")
                    parts.append("bgExit.watchdog=\(background.cumulativeAppWatchdogExitCount)")
                }
            }
            if !parts.isEmpty {
                Logger.shared.log("Perf", "MetricKit summary: \(parts.joined(separator: " "))")
            }

            // Everything else — launch time, hang time, animation and location metrics — only
            // exists as histograms. The system delivers at most one payload per day, so logging
            // the whole thing costs nothing and keeps the detail available.
            if let json = String(data: payload.jsonRepresentation(), encoding: .utf8) {
                Logger.shared.log("Perf", "MetricKit payload: \(json)")
            }
        }
    }

    @available(iOS 14.0, *)
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            if let hangs = payload.hangDiagnostics, !hangs.isEmpty {
                Logger.shared.log("Perf", "MetricKit: \(hangs.count) hang diagnostic(s)")
            }
            if let crashes = payload.crashDiagnostics, !crashes.isEmpty {
                Logger.shared.log("Perf", "MetricKit: \(crashes.count) crash diagnostic(s)")
            }
        }
    }
}
