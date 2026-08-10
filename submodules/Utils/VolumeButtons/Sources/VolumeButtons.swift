import Foundation
import UIKit
import AVFoundation
import AVKit
import SwiftSignalKit
import MediaPlayer
import AccountContext

private protocol VolumeButtonHandlerImpl: AnyObject {
}

/// Observes private UIApplication volume-button notifications (same hashes as
/// `PGCameraVolumeButtonHandler`) without linking LegacyComponents.
/// Falls back to `AVAudioSession.outputVolume` KVO when those notifications are quiet.
private final class NotificationVolumeHandlerImpl: NSObject, VolumeButtonHandlerImpl {
    private let performAction: (VolumeButtonsListener.Action) -> Void
    private var enabled: Bool = false
    private var volumeObservation: NSKeyValueObservation?
    private var lastVolume: Float
    private var ignoreKvoUntil: CFAbsoluteTime = 0

    init(performAction: @escaping (VolumeButtonsListener.Action) -> Void) {
        self.performAction = performAction
        self.lastVolume = AVAudioSession.sharedInstance().outputVolume
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.handleNotification(_:)),
            name: nil,
            object: nil
        )
        self.setEnabled(true)

        // Do not eagerly AVAudioSession.setActive(true) — that contends with
        // chat media playback and was a regression vs the ObjC handler. KVO
        // still works once the session is active for other reasons; private
        // volume-button notifications remain the primary path.
        self.volumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.old, .new]) { [weak self] _, change in
            guard let self, self.enabled else {
                return
            }
            if CFAbsoluteTimeGetCurrent() < self.ignoreKvoUntil {
                if let newValue = change.newValue {
                    self.lastVolume = newValue
                }
                return
            }
            guard let oldValue = change.oldValue ?? Optional(self.lastVolume), let newValue = change.newValue, oldValue != newValue else {
                return
            }
            self.lastVolume = newValue
            // KVO cannot observe release; emit a synthetic release so the public API stays complete.
            if newValue > oldValue {
                self.performAction(.up)
                self.performAction(.upRelease)
            } else {
                self.performAction(.down)
                self.performAction(.downRelease)
            }
        }
    }

    deinit {
        self.setEnabled(false)
        self.volumeObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    private func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        // Best-effort: mirror ObjC Freedom hook that turns on volume-button
        // monitoring. Absence of the private selector is fine — notifications
        // still arrive on many OS versions once another client enables them.
        let app = UIApplication.shared
        let selector = NSSelectorFromString("setWantsVolumeButtonEvents:")
        if app.responds(to: selector) {
            app.perform(selector, with: NSNumber(value: enabled))
        }
    }

    @objc private func handleNotification(_ notification: Notification) {
        guard self.enabled else {
            return
        }
        let name = notification.name.rawValue
        let nameLength = name.count
        guard nameLength == 46 || nameLength == 44 || nameLength == 42 || nameLength == 21 else {
            return
        }
        switch Self.murmurHash32(name) {
        case -1364315560: // _UIApplicationVolumeDownButtonDownNotification (0xaeae3258)
            self.suppressKvoEcho()
            self.performAction(.down)
        case 0x784c165e: // _UIApplicationVolumeDownButtonUpNotification
            self.suppressKvoEcho()
            self.performAction(.downRelease)
        case -1170117234: // _UIApplicationVolumeUpButtonDownNotification (0xba416d8e)
            self.suppressKvoEcho()
            self.performAction(.up)
        case 0x4074ecfb: // _UIApplicationVolumeUpButtonUpNotification
            self.suppressKvoEcho()
            self.performAction(.upRelease)
        case -119584760: // SystemVolumeDidChange (4175382536 as Int32)
            if let reason = notification.userInfo?["Reason"] as? String, reason == "ExplicitVolumeChange" {
                self.suppressKvoEcho()
                DispatchQueue.main.async {
                    self.performAction(.up)
                }
            }
        default:
            break
        }
    }

    private func suppressKvoEcho() {
        self.ignoreKvoUntil = CFAbsoluteTimeGetCurrent() + 0.15
        self.lastVolume = AVAudioSession.sharedInstance().outputVolume
    }

    /// MurmurHash3 x86_32 with seed -137723950 — matches `legacy_murMurHash32`.
    private static func murmurHash32(_ string: String) -> Int32 {
        let data = Array(string.utf8)
        let length = data.count
        let nblocks = length / 4
        // Seed -137723950 as UInt32 bits (avoid UInt32(bitPattern:) — TelegramCore also extends it).
        var h1: UInt32 = 0xf7c8c0d2

        let c1: UInt32 = 0xcc9e2d51
        let c2: UInt32 = 0x1b873593

        for i in 0 ..< nblocks {
            let i4 = i * 4
            var k1 = UInt32(data[i4])
                | (UInt32(data[i4 + 1]) << 8)
                | (UInt32(data[i4 + 2]) << 16)
                | (UInt32(data[i4 + 3]) << 24)
            k1 &*= c1
            k1 = (k1 << 15) | (k1 >> 17)
            k1 &*= c2

            h1 ^= k1
            h1 = (h1 << 13) | (h1 >> 19)
            h1 = h1 &* 5 &+ 0xe6546b64
        }

        var k1: UInt32 = 0
        let tailIndex = nblocks * 4
        switch length & 3 {
        case 3:
            k1 ^= UInt32(data[tailIndex + 2]) << 16
            fallthrough
        case 2:
            k1 ^= UInt32(data[tailIndex + 1]) << 8
            fallthrough
        case 1:
            k1 ^= UInt32(data[tailIndex])
            k1 &*= c1
            k1 = (k1 << 15) | (k1 >> 17)
            k1 &*= c2
            h1 ^= k1
        default:
            break
        }

        h1 ^= UInt32(length)
        h1 ^= h1 >> 16
        h1 &*= 0x85ebca6b
        h1 ^= h1 >> 13
        h1 &*= 0xc2b2ae35
        h1 ^= h1 >> 16
        return Int32(bitPattern: h1)
    }
}

@available(iOS 17.2, *)
private final class AVCaptureEventHandlerImpl: VolumeButtonHandlerImpl {
    private weak var context: SharedAccountContext?
    private let interaction: AVCaptureEventInteraction

    init(
        context: SharedAccountContext,
        performAction: @escaping (VolumeButtonsListener.Action) -> Void
    ) {
        self.context = context
        self.interaction = AVCaptureEventInteraction(
            primary: { event in
                switch event.phase {
                case .began:
                    performAction(.down)
                case .ended:
                    performAction(.downRelease)
                case .cancelled:
                    performAction(.downRelease)
                @unknown default:
                    break
                }
            },
            secondary: { event in
                switch event.phase {
                case .began:
                    performAction(.up)
                case .ended:
                    performAction(.upRelease)
                case .cancelled:
                    performAction(.upRelease)
                @unknown default:
                    break
                }
            }
        )
        self.interaction.isEnabled = true
        context.mainWindow?.viewController?.view.addInteraction(self.interaction)
    }

    deinit {
        self.interaction.isEnabled = false
        self.context?.mainWindow?.viewController?.view.removeInteraction(self.interaction)
    }
}

/// iOS 17.2+ non-camera path: same private `MPVolumeControllerSystemDataSource`
/// that `PGCameraVolumeButtonHandler` instantiates, plus notification / KVO listening.
@available(iOS 17.2, *)
private final class SystemVolumeDataSourceHandlerImpl: VolumeButtonHandlerImpl {
    private let notificationHandler: NotificationVolumeHandlerImpl
    private var dataSource: NSObject?

    init(performAction: @escaping (VolumeButtonsListener.Action) -> Void) {
        self.notificationHandler = NotificationVolumeHandlerImpl(performAction: performAction)
        // "MPVolumeControllerSystemDataSource" encoded the same way as ObjC (+1 / -1).
        let className = String(bytes: "NQWpmvnfDpouspmmfsTztufnEbubTpvsdf".utf8.map { UInt8(($0 &- 1) & 0xff) }, encoding: .utf8)
        if let className, let cls = NSClassFromString(className) as? NSObject.Type {
            self.dataSource = cls.init()
        }
    }
}

public class VolumeButtonsListener {
    private final class ListenerReference {
        let id: Int
        weak var listener: VolumeButtonsListener?

        init(id: Int, listener: VolumeButtonsListener) {
            self.id = id
            self.listener = listener
        }
    }

    fileprivate enum Action {
        case up
        case upRelease
        case down
        case downRelease
    }

    private final class SharedContext: NSObject {
        private var handler: VolumeButtonHandlerImpl?
        private var cameraSpecificHandler: VolumeButtonHandlerImpl?

        private weak var sharedAccountContext: SharedAccountContext?

        private var nextListenerId: Int = 0
        private var listeners: [ListenerReference] = []

        override init() {
            super.init()
        }

        func add(listener: VolumeButtonsListener) -> Int {
            self.sharedAccountContext = listener.sharedAccountContext

            let id = self.nextListenerId
            self.nextListenerId += 1

            self.listeners.append(ListenerReference(id: id, listener: listener))
            self.updateListeners()

            return id
        }

        func update(id: Int) {
            self.updateListeners()
        }

        func remove(id: Int) {
            if let index = self.listeners.firstIndex(where: { $0.id == id }) {
                self.listeners.remove(at: index)
                self.updateListeners()
            }
        }

        private func performAction(_ action: Action, isCameraSpecific: Bool) {
            for i in (0 ..< self.listeners.count).reversed() {
                if let listener = self.listeners[i].listener, listener.isActive, listener.isCameraSpecific == isCameraSpecific {
                    switch action {
                    case .up:
                        listener.upPressed()
                    case .upRelease:
                        listener.upReleased()
                    case .down:
                        listener.downPressed()
                    case .downRelease:
                        listener.downReleased()
                    }
                }
            }
        }

        private func updateListeners() {
            var isGeneralActive = false
            var isCameraSpecificActive = false

            for i in (0 ..< self.listeners.count).reversed() {
                if let listener = self.listeners[i].listener {
                    if listener.isActive {
                        if #available(iOS 17.2, *) {
                            if listener.isCameraSpecific {
                                isCameraSpecificActive = true
                            } else {
                                isGeneralActive = true
                            }
                        } else {
                            isGeneralActive = true
                        }
                    }
                } else {
                    self.listeners.remove(at: i)
                }
            }

            if isGeneralActive {
                if self.handler == nil {
                    let performAction: (VolumeButtonsListener.Action) -> Void = { [weak self] action in
                        self?.performAction(action, isCameraSpecific: false)
                    }
                    if #available(iOS 17.2, *) {
                        self.handler = SystemVolumeDataSourceHandlerImpl(performAction: performAction)
                    } else {
                        self.handler = NotificationVolumeHandlerImpl(performAction: performAction)
                    }
                }
            } else {
                self.handler = nil
            }

            if isCameraSpecificActive {
                if self.cameraSpecificHandler == nil {
                    if let sharedAccountContext = self.sharedAccountContext {
                        let performAction: (VolumeButtonsListener.Action) -> Void = { [weak self] action in
                            self?.performAction(action, isCameraSpecific: true)
                        }
                        if #available(iOS 17.2, *) {
                            self.cameraSpecificHandler = AVCaptureEventHandlerImpl(
                                context: sharedAccountContext,
                                performAction: performAction
                            )
                        } else {
                            self.cameraSpecificHandler = NotificationVolumeHandlerImpl(performAction: performAction)
                        }
                    }
                }
            } else {
                self.cameraSpecificHandler = nil
            }
        }
    }

    fileprivate let sharedAccountContext: SharedAccountContext
    fileprivate let isCameraSpecific: Bool

    private static var sharedContext: SharedContext = {
        return SharedContext()
    }()

    fileprivate let upPressed: () -> Void
    fileprivate let upReleased: () -> Void
    fileprivate let downPressed: () -> Void
    fileprivate let downReleased: () -> Void

    private var index: Int?

    fileprivate var isActive: Bool = false
    private var disposable: Disposable?

    public init(
        sharedContext: SharedAccountContext,
        isCameraSpecific: Bool,
        shouldBeActive: Signal<Bool, NoError>,
        upPressed: @escaping () -> Void,
        upReleased: @escaping () -> Void = {},
        downPressed: @escaping () -> Void,
        downReleased: @escaping () -> Void = {}
    ) {
        self.sharedAccountContext = sharedContext
        self.isCameraSpecific = isCameraSpecific
        self.upPressed = upPressed
        self.upReleased = upReleased
        self.downPressed = downPressed
        self.downReleased = downReleased

        self.index = VolumeButtonsListener.sharedContext.add(listener: self)

        self.disposable = (shouldBeActive
        |> distinctUntilChanged
        |> deliverOnMainQueue).start(next: { [weak self] value in
            guard let self, let index = self.index else {
                return
            }
            self.isActive = value
            VolumeButtonsListener.sharedContext.update(id: index)
        })
    }

    deinit {
        if let index = self.index {
            VolumeButtonsListener.sharedContext.remove(id: index)
        }
        self.disposable?.dispose()
    }
}
