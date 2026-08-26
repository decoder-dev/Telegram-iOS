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

    /// Diagnostics are the half of MetricKit that says *why* something went wrong, and unlike the
    /// metric payloads they arrive with a call-stack tree attached. This used to log the count and
    /// nothing else, which is the worst of both worlds: a crash loop left a log full of
    /// "1 crash diagnostic(s)" and not one frame to act on, while the system had handed the app
    /// every stack it needed.
    ///
    /// So each diagnostic now gets a one-line summary — termination reason, signal, exception,
    /// build — that is greppable without parsing anything, followed by the payload's own JSON, which
    /// carries the call-stack tree. The metric branch above already logs its payload whole for the
    /// same reason. Diagnostics are rare when the app is healthy and exactly what is wanted when it
    /// is not, so the size is worth it.
    @available(iOS 14.0, *)
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            if let hangs = payload.hangDiagnostics, !hangs.isEmpty {
                Logger.shared.log("Perf", "MetricKit: \(hangs.count) hang diagnostic(s)")
                for hang in hangs {
                    Logger.shared.log("Perf", "MetricKit hang: duration=\(hang.hangDuration.value)\(hang.hangDuration.unit.symbol) build=\(hang.metaData.applicationBuildVersion) os=\(hang.metaData.osVersion)")
                }
            }
            if let crashes = payload.crashDiagnostics, !crashes.isEmpty {
                Logger.shared.log("Perf", "MetricKit: \(crashes.count) crash diagnostic(s)")
                for crash in crashes {
                    var parts: [String] = []
                    if let reason = crash.terminationReason {
                        parts.append("reason=\(reason)")
                    }
                    if let signal = crash.signal {
                        parts.append("signal=\(signal)")
                    }
                    if let exceptionType = crash.exceptionType {
                        parts.append("exceptionType=\(exceptionType)")
                    }
                    if let exceptionCode = crash.exceptionCode {
                        parts.append("exceptionCode=\(exceptionCode)")
                    }
                    if let regionInfo = crash.virtualMemoryRegionInfo {
                        // A bad-access crash names the region it touched here, which separates a
                        // wild pointer from a use-after-free without reading the stack at all.
                        parts.append("vmRegion=\(regionInfo.replacingOccurrences(of: "\n", with: " "))")
                    }
                    parts.append("build=\(crash.metaData.applicationBuildVersion)")
                    parts.append("os=\(crash.metaData.osVersion)")
                    Logger.shared.log("Perf", "MetricKit crash: \(parts.joined(separator: " "))")
                }
            }
            if let json = String(data: payload.jsonRepresentation(), encoding: .utf8) {
                Logger.shared.log("Perf", "MetricKit diagnostic payload: \(json)")
            }
        }
    }
}
