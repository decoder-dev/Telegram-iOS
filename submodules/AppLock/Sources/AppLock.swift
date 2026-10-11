import Foundation
import Darwin
import UIKit
import TelegramCore
import Display
import SwiftSignalKit
import MonotonicTime
import AccountContext
import TelegramPresentationData
import PasscodeUI
import TelegramUIPreferences
import AppLockState
import PassKit
#if canImport(WidgetKit)
import WidgetKit
#endif
import PasscodeCore

private func isLocked(passcodeSettings: PresentationPasscodeSettings, state: LockState) -> Bool {
    if state.isManuallyLocked {
        return true
    } else if let autolockTimeout = passcodeSettings.autolockTimeout {
        var bootTimestamp: Int32 = 0
        let uptime = getDeviceUptimeSeconds(&bootTimestamp)
        let timestamp = MonotonicTimestamp(bootTimestamp: bootTimestamp, uptime: uptime)
        
        let applicationActivityTimestamp = state.applicationActivityTimestamp
        
        if let applicationActivityTimestamp = applicationActivityTimestamp {
            if timestamp.bootTimestamp != applicationActivityTimestamp.bootTimestamp {
                return true
            }
            if timestamp.uptime >= applicationActivityTimestamp.uptime + autolockTimeout {
                return true
            }
        } else {
            return true
        }
    }
    return false
}

private func reloadWidgetTimelinesAfterLockStateChange() {
    #if canImport(WidgetKit)
    if #available(iOS 14.0, *) {
        #if arch(arm64) || arch(i386) || arch(x86_64)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    #endif
}

private struct AppLockBiometricAuthenticationState {
    private var isApplicationActive = false
    private var isApplicationInForeground = false
    private var pendingRequests = Set<UUID>()
    private(set) var suppressCoveringView = false

    mutating func update(isApplicationActive: Bool, isApplicationInForeground: Bool) {
        if !isApplicationInForeground {
            self.pendingRequests.removeAll()
            self.suppressCoveringView = false
        } else if isApplicationActive {
            self.suppressCoveringView = false
        } else if self.isApplicationActive && self.isApplicationInForeground {
            self.suppressCoveringView = !self.pendingRequests.isEmpty
            self.pendingRequests.removeAll()
        }
        self.isApplicationActive = isApplicationActive
        self.isApplicationInForeground = isApplicationInForeground
    }

    mutating func begin() -> UUID? {
        guard self.isApplicationActive && self.isApplicationInForeground else { return nil }
        let id = UUID()
        self.pendingRequests.insert(id)
        return id
    }

    mutating func end(_ id: UUID) {
        self.pendingRequests.remove(id)
    }
}

public final class AppLockContextImpl: AppLockContext {
    private let rootPath: String
    private let syncQueue = Queue()
    
    private var disposable: Disposable?
    private var autolockTimeoutDisposable: Disposable?
    
    private let applicationBindings: TelegramApplicationBindings
    private let accountManager: AccountManager<TelegramAccountManagerTypes>
    private let presentationDataSignal: Signal<PresentationData, NoError>
    private let window: Window1?
    private let rootController: UIViewController?
    
    private var coveringView: LockedWindowCoveringView?
    private var passcodeController: PasscodeEntryController?
    
    private var timestampRenewTimer: SwiftSignalKit.Timer?
    
    private var currentStateValue: LockState
    private let currentState = Promise<LockState>()
    
    private let autolockTimeout = ValuePromise<Int32?>(nil, ignoreRepeated: true)
    private let autolockReportTimeout = ValuePromise<Int32?>(nil, ignoreRepeated: true)
    
    private let lockStatus = AppLockStatus()
    public var isPasscodeLocked: Signal<Bool, NoError> {
        return self.lockStatus.isPasscodeLocked
    }

    public var isCurrentlyLocked: Signal<Bool, NoError> {
        return self.lockStatus.isCurrentlyLocked
    }
    
    private var lastActiveTimestamp: Double?
    private var lastActiveValue: Bool = false
    private var lastForegroundValue: Bool = true
    private var biometricAuthenticationState = AppLockBiometricAuthenticationState()
    private var suppressAutomaticBiometrics = false
    
    public init(rootPath: String, window: Window1?, rootController: UIViewController?, applicationBindings: TelegramApplicationBindings, accountManager: AccountManager<TelegramAccountManagerTypes>, presentationDataSignal: Signal<PresentationData, NoError>, lockIconInitialFrame: @escaping () -> CGRect?) {
        assert(Queue.mainQueue().isCurrent())
        
        self.applicationBindings = applicationBindings
        self.accountManager = accountManager
        self.presentationDataSignal = presentationDataSignal
        self.rootPath = rootPath
        self.window = window
        self.rootController = rootController
        
        if let data = try? Data(contentsOf: URL(fileURLWithPath: appLockStatePath(rootPath: self.rootPath))), let current = try? JSONDecoder().decode(LockState.self, from: data) {
            self.currentStateValue = current
        } else {
            self.currentStateValue = LockState()
        }
        self.autolockTimeout.set(self.currentStateValue.autolockTimeout)
        
        self.disposable = (combineLatest(queue: .mainQueue(),
            accountManager.accessChallengeData(),
            accountManager.sharedData(keys: Set([ApplicationSpecificSharedDataKeys.presentationPasscodeSettings, ApplicationSpecificSharedDataKeys.forkExtrasSettings])),
            presentationDataSignal,
            applicationBindings.applicationIsActive,
            applicationBindings.applicationInForeground,
            self.currentState.get()
        )
        |> deliverOnMainQueue).startStrict(next: { [weak self] accessChallengeData, sharedData, presentationData, isApplicationActive, isApplicationInForeground, state in
            guard let strongSelf = self else {
                return
            }

            strongSelf.biometricAuthenticationState.update(isApplicationActive: isApplicationActive, isApplicationInForeground: isApplicationInForeground)
            
            let passcodeSettings: PresentationPasscodeSettings = sharedData.entries[ApplicationSpecificSharedDataKeys.presentationPasscodeSettings]?.get(PresentationPasscodeSettings.self) ?? .defaultSettings
            let forkExtras: ForkExtrasSettings = sharedData.entries[ApplicationSpecificSharedDataKeys.forkExtrasSettings]?.get(ForkExtrasSettings.self) ?? .defaultSettings

            if !isApplicationInForeground {
                strongSelf.suppressAutomaticBiometrics = false
            }
            
            let timestamp = CFAbsoluteTimeGetCurrent()
            var becameActiveRecently = false
            var justEnteredBackground = false
            if isApplicationActive {
                if !strongSelf.lastActiveValue {
                    strongSelf.lastActiveValue = true
                    strongSelf.lastActiveTimestamp = timestamp
                    
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: appLockStatePath(rootPath: strongSelf.rootPath))), let current = try? JSONDecoder().decode(LockState.self, from: data) {
                        strongSelf.currentStateValue = current
                    }
                }
                
                if let lastActiveTimestamp = strongSelf.lastActiveTimestamp {
                    if lastActiveTimestamp + 0.5 > timestamp {
                        becameActiveRecently = true
                    }
                }
            } else {
                strongSelf.lastActiveValue = false
            }
            
            if isApplicationInForeground {
                strongSelf.lastForegroundValue = true
            } else if strongSelf.lastForegroundValue {
                justEnteredBackground = true
                strongSelf.lastForegroundValue = false
            }
            
            var shouldDisplayCoveringView = false
            var isCurrentlyLocked = false
            
            if !accessChallengeData.data.isLockable {
                if let passcodeController = strongSelf.passcodeController {
                    strongSelf.passcodeController = nil
                    passcodeController.dismiss()
                }
                
                strongSelf.autolockTimeout.set(nil)
                strongSelf.autolockReportTimeout.set(nil)
            } else {
                // Instant Passcode covers and locks on resign-active (Control Center,
                // app switcher, permission sheets), not only the background edge.
                if !isApplicationActive && !strongSelf.biometricAuthenticationState.suppressCoveringView {
                    if forkExtras.instantPasscodeLock {
                        strongSelf.lock()
                        shouldDisplayCoveringView = true
                    }
                    if forkExtras.instantPasscodeLock || passcodeSettings.autolockTimeout != nil {
                        shouldDisplayCoveringView = true
                    }
                }
                
                if justEnteredBackground && forkExtras.instantPasscodeLock {
                    strongSelf.lock()
                    shouldDisplayCoveringView = true
                } else if !isApplicationInForeground && state.isManuallyLocked {
                    shouldDisplayCoveringView = true
                }
                
                if !isApplicationActive {
                    if let autolockTimeout = passcodeSettings.autolockTimeout {
                        strongSelf.autolockReportTimeout.set(autolockTimeout)
                    } else if state.isManuallyLocked {
                        strongSelf.autolockReportTimeout.set(1)
                    } else {
                        strongSelf.autolockReportTimeout.set(nil)
                    }
                } else {
                    strongSelf.autolockReportTimeout.set(nil)
                }
                
                strongSelf.autolockTimeout.set(passcodeSettings.autolockTimeout)
                
                if isLocked(passcodeSettings: passcodeSettings, state: state) {
                    isCurrentlyLocked = true
                    
                    let biometrics: PasscodeEntryControllerBiometricsMode
                    if passcodeSettings.enableBiometrics {
                        biometrics = .enabled(passcodeSettings.biometricsDomainState)
                    } else {
                        biometrics = .none
                    }
                    
                    if let passcodeController = strongSelf.passcodeController {
                        if becameActiveRecently, !strongSelf.suppressAutomaticBiometrics, case .enabled = biometrics, isApplicationActive {
                            passcodeController.requestBiometrics()
                        }
                        passcodeController.ensureInputFocused()
                    } else {
                        let passcodeController = PasscodeEntryController(applicationBindings: strongSelf.applicationBindings, accountManager: strongSelf.accountManager, appLockContext: strongSelf, presentationData: presentationData, presentationDataSignal: strongSelf.presentationDataSignal, statusBarHost: window?.statusBarHost, challengeData: accessChallengeData.data, biometrics: biometrics, arguments: PasscodeEntryControllerPresentationArguments(animated: !becameActiveRecently || strongSelf.suppressAutomaticBiometrics, lockIconInitialFrame: {
                            if let lockViewFrame = lockIconInitialFrame() {
                                return lockViewFrame
                            } else {
                                return CGRect()
                            }
                        }))
                        if becameActiveRecently, !strongSelf.suppressAutomaticBiometrics, isApplicationActive {
                            passcodeController.presentationCompleted = { [weak self, weak passcodeController] in
                                if case .enabled = biometrics, self?.suppressAutomaticBiometrics == false {
                                    passcodeController?.requestBiometrics()
                                }
                                passcodeController?.ensureInputFocused()
                            }
                        }
                        passcodeController.presentedOverCoveringView = true
                        passcodeController.isOpaqueWhenInOverlay = true
                        strongSelf.passcodeController = passcodeController
                        if let rootViewController = strongSelf.rootController {
                            if let _ = rootViewController.presentedViewController as? UIActivityViewController {
                            } else if let _ = rootViewController.presentedViewController as? PKPaymentAuthorizationViewController {
                            } else {
                                rootViewController.dismiss(animated: false, completion: nil)
                            }
                        }
                        strongSelf.window?.present(passcodeController, on: .passcode)
                    }
                } else if let passcodeController = strongSelf.passcodeController {
                    strongSelf.passcodeController = nil
                    passcodeController.dismiss()
                }
            }
            
            strongSelf.updateTimestampRenewTimer(shouldRun: isApplicationActive && !isCurrentlyLocked)
            strongSelf.lockStatus.update(isPasscodeLocked: isCurrentlyLocked, isApplicationActive: isApplicationActive, isApplicationInForeground: isApplicationInForeground)
            
            if shouldDisplayCoveringView {
                if !isApplicationActive {
                    strongSelf.hideKeyboardForPrivacyCover()
                }
                if strongSelf.coveringView == nil, let window = strongSelf.window {
                    let coveringView = LockedWindowCoveringView(theme: presentationData.theme)
                    // Never take a drawHierarchy snapshot here — full-window capture + blur
                    // heats the device on every background/lock. Solid theme cover is enough;
                    // PasscodeEntryController overlays it when locked.
                    coveringView.updateSnapshot(nil)
                    strongSelf.coveringView = coveringView
                    window.coveringView = coveringView
                    
                    if let rootViewController = strongSelf.rootController {
                        if let _ = rootViewController.presentedViewController as? UIActivityViewController {
                        } else if let _ = rootViewController.presentedViewController as? PKPaymentAuthorizationViewController {
                        } else {
                            rootViewController.dismiss(animated: false, completion: nil)
                        }
                    }
                }
            } else {
                if let _ = strongSelf.coveringView {
                    strongSelf.coveringView = nil
                    strongSelf.window?.coveringView = nil
                }
            }
        })
        
        self.currentState.set(.single(self.currentStateValue))
        
        self.autolockTimeoutDisposable = (self.autolockTimeout.get()
        |> deliverOnMainQueue).startStrict(next: { [weak self] autolockTimeout in
            self?.updateLockState { state in
                var state = state
                state.autolockTimeout = autolockTimeout
                return state
            }
        })
    }
    
    deinit {
        self.disposable?.dispose()
        self.autolockTimeoutDisposable?.dispose()
    }

    public func beginBiometricAuthentication() -> Disposable {
        assert(Queue.mainQueue().isCurrent())
        guard let id = self.biometricAuthenticationState.begin() else { return EmptyDisposable }
        return ActionDisposable { [weak self] in
            if Queue.mainQueue().isCurrent() {
                self?.biometricAuthenticationState.end(id)
            } else {
                Queue.mainQueue().async { [weak self] in
                    self?.biometricAuthenticationState.end(id)
                }
            }
        }
    }
    
    private func updateTimestampRenewTimer(shouldRun: Bool) {
        if shouldRun {
            if self.timestampRenewTimer == nil {
                let timestampRenewTimer = SwiftSignalKit.Timer(timeout: 5.0, repeat: true, completion: { [weak self] in
                    guard let strongSelf = self else {
                        return
                    }
                    strongSelf.updateApplicationActivityTimestamp()
                }, queue: .mainQueue())
                self.timestampRenewTimer = timestampRenewTimer
                timestampRenewTimer.start()
            }
        } else {
            if let timestampRenewTimer = self.timestampRenewTimer {
                self.timestampRenewTimer = nil
                timestampRenewTimer.invalidate()
            }
        }
    }
    
    private func updateApplicationActivityTimestamp() {
        self.updateLockState { state in
            var bootTimestamp: Int32 = 0
            let uptime = getDeviceUptimeSeconds(&bootTimestamp)
            
            var state = state
            state.applicationActivityTimestamp = MonotonicTimestamp(bootTimestamp: bootTimestamp, uptime: uptime)
            return state
        }
    }
    
    private func updateLockState(_ f: @escaping (LockState) -> LockState) {
        Queue.mainQueue().async {
            let updatedState = f(self.currentStateValue)
            if updatedState != self.currentStateValue {
                let wasLocked = isAppLocked(state: self.currentStateValue)
                self.currentStateValue = updatedState
                self.currentState.set(.single(updatedState))
                
                let path = appLockStatePath(rootPath: self.rootPath)
                let nowLocked = isAppLocked(state: updatedState)
                let reloadWidgets = wasLocked != nowLocked
                
                self.syncQueue.async {
                    if let data = try? JSONEncoder().encode(updatedState) {
                        let _ = try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
                    }
                    if reloadWidgets {
                        reloadWidgetTimelinesAfterLockStateChange()
                    }
                }
            }
        }
    }
    
    public func _internalCrashForPasscodeMigrationTest(isLocked: Bool) throws -> Never {
        var writeError: Error?
        self.syncQueue.sync {
            do {
                let data = try JSONEncoder().encode(LockState(isManuallyLocked: isLocked))
                try data.write(to: URL(fileURLWithPath: appLockStatePath(rootPath: self.rootPath)), options: .atomic)
                abort()
            } catch {
                writeError = error
            }
        }
        throw writeError!
    }

    public var invalidAttempts: Signal<AccessChallengeAttempts?, NoError> {
        return self.currentState.get()
        |> map { state in
            return state.unlockAttempts.flatMap { unlockAttempts in
                return AccessChallengeAttempts(count: unlockAttempts.count, bootTimestamp: unlockAttempts.timestamp.bootTimestamp, uptime: unlockAttempts.timestamp.uptime)
            }
        }
    }
    
    public var autolockDeadline: Signal<Int32?, NoError> {
        return self.autolockReportTimeout.get()
        |> distinctUntilChanged
        |> map { value -> Int32? in
            if let value = value {
                return Int32(Date().timeIntervalSince1970) + value
            } else {
                return nil
            }
        }
    }
    
    private func hideKeyboardForPrivacyCover() {
        self.window?.hostView.containerView.endEditing(true)
        self.window?.hostView.eventView.endEditing(true)
        self.applicationBindings.getTopWindow()?.endEditing(true)
        self.rootController?.view.endEditing(true)
    }
    
    public func lock() {
        // Widget timelines reload after lockState.json is persisted in updateLockState.
        PasscodeSession.setApplicationAvailable(false)
        self.updateLockState { state in
            // Face ID may still send active events after the user manually locks.
            self.suppressAutomaticBiometrics = true
            var state = state
            state.isManuallyLocked = true
            return state
        }
    }
    
    public func unlock() {
        self.updateLockState { state in
            var state = state
            
            state.unlockAttempts = nil
            
            state.isManuallyLocked = false
            
            var bootTimestamp: Int32 = 0
            let uptime = getDeviceUptimeSeconds(&bootTimestamp)
            let timestamp = MonotonicTimestamp(bootTimestamp: bootTimestamp, uptime: uptime)
            state.applicationActivityTimestamp = timestamp
            
            return state
        }
    }
    
    public func failedUnlockAttempt() {
        self.updateLockState { state in
            var state = state
            var unlockAttempts = state.unlockAttempts ?? UnlockAttempts(count: 0, timestamp: MonotonicTimestamp(bootTimestamp: 0, uptime: 0))
            
            unlockAttempts.count += 1
            
            var bootTimestamp: Int32 = 0
            let uptime = getDeviceUptimeSeconds(&bootTimestamp)
            let timestamp = MonotonicTimestamp(bootTimestamp: bootTimestamp, uptime: uptime)
            
            unlockAttempts.timestamp = timestamp
            state.unlockAttempts = unlockAttempts
            return state
        }
    }
}
