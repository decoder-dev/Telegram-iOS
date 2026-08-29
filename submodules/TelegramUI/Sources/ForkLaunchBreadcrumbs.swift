import Foundation
import Darwin
import TelegramCore

/// Records where the app was when it died, so an intermittent launch crash can be diagnosed from
/// the next launch instead of from a symptom description.
///
/// There is no other crash handler in this app, so nothing here competes with one. Every handler
/// restores the default disposition and re-raises, which leaves the operating system's own crash
/// report untouched — this only adds a breadcrumb the OS report cannot carry: *which launch stage*
/// was running.
///
/// Async-signal-safety is the whole design constraint of the signal path. Inside a signal handler
/// almost nothing is legal: no allocation, no locks, no Foundation, no `String`. So the file
/// descriptor and the record buffer are both prepared at install time, and the handler does
/// nothing but fill four bytes and `write()` them. The `NSException` handler is not in signal
/// context and may use Foundation freely.
public enum ForkLaunchBreadcrumbs {
    /// Stages, written as a single byte, so the value must stay under 256.
    ///
    /// The launch half runs in order. The runtime half does not: after `didBecomeActive` every
    /// crash reported the same value, which made a record of a crash two minutes in say nothing
    /// about where it happened. These name what was on screen instead, each overwriting the last,
    /// so the byte answers "doing what" rather than only "past launch".
    ///
    /// Numbered from 20 so launch stages keep room to grow without renumbering anything a shipped
    /// build may already have written to disk.
    public enum Stage: UInt8 {
        case didFinishLaunchingBegan = 1
        case accountManagerOpened = 2
        case loggerReady = 3
        case sharedContextReady = 4
        case rootControllerReady = 5
        case didFinishLaunchingReturned = 6
        case didBecomeActive = 7

        case chatListVisible = 20
        case chatOpened = 21
        case composerActive = 22
        case contextMenuOpen = 23
        case reactionSheetOpen = 24
        case mediaGalleryOpen = 25
        case settingsOpen = 26
        case enteredBackground = 27
    }

    private static let recordSize = 4
    private static let markerCrash: UInt8 = 0x43       // 'C'
    private static let markerException: UInt8 = 0x45   // 'E'

    private static var fileDescriptor: Int32 = -1
    private static var recordBuffer: UnsafeMutablePointer<UInt8>?
    /// Touched from the signal handler, so it is a plain global rather than anything with a lock.
    private static var lastStage: UInt8 = 0
    private static var installed = false

    private static var filePath: String {
        return NSHomeDirectory() + "/Library/Caches/fork_launch_crash"
    }

    /// Call as early as possible in `didFinishLaunchingWithOptions`, before anything that can fault.
    /// Returns the previous launch's record, if the previous launch died, so the caller can log it
    /// once a logger exists.
    @discardableResult
    public static func install() -> String? {
        if self.installed {
            return nil
        }
        self.installed = true
        // Touched here so its lazy static initialiser has already run by the time a handler can
        // reach it. First access to a Swift static goes through swift_once, which takes a lock —
        // legal here, not legal in signal context.
        self.lastStage = 0

        let previous = self.consumePreviousRecord()

        let path = self.filePath
        self.fileDescriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard self.fileDescriptor >= 0 else {
            return previous
        }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: self.recordSize)
        buffer.initialize(repeating: 0, count: self.recordSize)
        buffer[self.recordSize - 1] = 0x0A
        self.recordBuffer = buffer

        for signalNumber in [SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
            signal(signalNumber, forkLaunchCrashSignalHandler)
        }

        // Chain, do not replace: something else may already be watching (a crash reporter, the
        // host app), and swallowing its handler would trade one blind spot for another.
        let previousExceptionHandler = NSGetUncaughtExceptionHandler()
        ForkLaunchBreadcrumbs.previousExceptionHandler = previousExceptionHandler

        NSSetUncaughtExceptionHandler { exception in
            // Not signal context: Foundation is allowed here, and the four-byte record is not
            // nearly enough. A MetricKit payload gives a crash stack as binary UUIDs and byte
            // offsets, which needs a matching dSYM to mean anything — and one of the crashes in
            // a recent log was exactly this: SIGABRT with the Foundation → objc_exception_throw
            // → libc++abi → abort shape, thrown from TelegramCore, and no way to name it. The
            // exception knows its own name, reason and frames; writing them costs nothing at a
            // point where the process is ending anyway.
            ForkLaunchBreadcrumbs.writeExceptionRecord(name: exception.name.rawValue, reason: exception.reason ?? "")

            Logger.shared.log("Crash", "uncaught exception \(exception.name.rawValue): \(exception.reason ?? "no reason")")
            for (index, frame) in exception.callStackSymbols.enumerated() {
                Logger.shared.log("Crash", "  \(index): \(frame)")
            }
            // The process is about to die; without this the lines are still on the log queue.
            Logger.shared.sync()

            ForkLaunchBreadcrumbs.previousExceptionHandler?(exception)
        }

        return previous
    }

    /// The handler that was installed before ours, called after we have written our own record.
    private static var previousExceptionHandler: (@convention(c) (NSException) -> Void)?

    /// Record that launch reached `stage`. Cheap enough to call unconditionally.
    public static func mark(_ stage: Stage) {
        self.lastStage = stage.rawValue
    }

    fileprivate static func writeCrashRecord(signalNumber: Int32) {
        guard self.fileDescriptor >= 0, let buffer = self.recordBuffer else {
            return
        }
        buffer[0] = self.markerCrash
        buffer[1] = UInt8(truncatingIfNeeded: signalNumber)
        buffer[2] = self.lastStage
        _ = write(self.fileDescriptor, buffer, self.recordSize)
        fsync(self.fileDescriptor)
    }

    private static func writeExceptionRecord(name: String, reason: String) {
        guard self.fileDescriptor >= 0, let buffer = self.recordBuffer else {
            return
        }
        buffer[0] = self.markerException
        buffer[1] = 0
        buffer[2] = self.lastStage
        _ = write(self.fileDescriptor, buffer, self.recordSize)
        let text = "\(name): \(reason)\n"
        _ = text.utf8CString.withUnsafeBufferPointer { pointer -> Int in
            guard let base = pointer.baseAddress else {
                return 0
            }
            // utf8CString includes the terminating NUL; do not write it.
            return write(self.fileDescriptor, base, max(0, pointer.count - 1))
        }
        fsync(self.fileDescriptor)
    }

    private static func stageName(_ raw: UInt8) -> String {
        guard let stage = Stage(rawValue: raw) else {
            return "none (crashed before the first mark)"
        }
        return "\(stage)"
    }

    /// Reads and deletes the record left by a previous launch. Nil when the previous launch exited
    /// normally: a clean run truncates the file on install and writes nothing to it.
    private static func consumePreviousRecord() -> String? {
        let path = self.filePath
        defer {
            // Removed either way. A record that cannot be parsed is worse than no record, and
            // leaving it behind would report the same stale crash on every future launch.
            try? FileManager.default.removeItem(atPath: path)
        }
        guard let data = FileManager.default.contents(atPath: path), data.count >= self.recordSize else {
            return nil
        }
        let bytes = [UInt8](data)
        let stage = self.stageName(bytes[2])
        let trailing = data.count > self.recordSize
            ? String(data: data.subdata(in: self.recordSize ..< data.count), encoding: .utf8) ?? ""
            : ""

        switch bytes[0] {
        case self.markerCrash:
            return "previous launch died on signal \(Int32(bytes[1])), last stage reached: \(stage)"
        case self.markerException:
            return "previous launch died on an uncaught exception, last stage reached: \(stage)\n\(trailing)"
        default:
            return nil
        }
    }
}

/// Top-level so it can be used as a C function pointer: a closure that captures nothing still will
/// not convert if it is declared inside a type in some toolchain versions, and this must not be a
/// closure that allocates.
private func forkLaunchCrashSignalHandler(_ signalNumber: Int32) {
    ForkLaunchBreadcrumbs.writeCrashRecord(signalNumber: signalNumber)
    // Hand the fault back to the default handler so the OS still writes its own report.
    signal(signalNumber, SIG_DFL)
    raise(signalNumber)
}
