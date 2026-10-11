import Foundation
import UIKit
import AVFoundation
import SwiftSignalKit
import TelegramAudio
import TelegramCore

/// Keeps the process running while the screen is locked by looping digital silence through the audio session.
///
/// A sideloaded build receives no push notifications (APNs delivers only to the official bundle id), so a call or a message
/// can reach it only over its own MTProto connection, and iOS suspends the app a few seconds after it leaves the screen. An
/// app that is playing audio is not suspended, which keeps the connection up and lets an incoming call be reported to
/// CallKit while the phone is locked.
///
/// The audio session is taken through `ManagedAudioSession`, mixing with others, so a call, a voice message or music
/// takes over as usual and this resumes afterwards. It costs battery and does not survive memory pressure.
final class ForkBackgroundKeepAlive {
    static let shared = ForkBackgroundKeepAlive()
    
    private var sessionDisposable: Disposable?
    private var player: AVAudioPlayer?
    private var isEnabled = false
    /// The audio session is ours (the holder is active); false while a call, a voice message or music has it.
    private var hasSession = false
    private var isAppActive = true
    private var restartTimer: SwiftSignalKit.Timer?
    private var observers: [NSObjectProtocol] = []
    
    /// True while the silence keeps the process running. `SharedWakeupManager` keeps the accounts' update
    /// connections up for as long as this holds: a process kept alive with its MTProto connection asleep
    /// would still miss the call. Main queue only.
    var keepsNetworkAlive: Bool {
        return self.isEnabled && !self.isAppActive
    }
    
    private init() {
    }
    
    /// Main queue only; `shared` may first be touched from a settings queue.
    private func setUpObserversIfNeeded() {
        if !self.observers.isEmpty {
            return
        }
        let center = NotificationCenter.default
        self.isAppActive = UIApplication.shared.applicationState == .active
        // The silence is only needed while the app is off screen. Playing it in the foreground cost battery for nothing.
        self.observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.updateAppActive(false)
        }))
        self.observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.updateAppActive(false)
        }))
        self.observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.updateAppActive(true)
        }))
        // Siri, an alarm or a cellular call stop the player, and nothing restarted it: the app was suspended
        // after the first interruption of the night.
        self.observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main, using: { [weak self] notification in
            guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, let type = AVAudioSession.InterruptionType(rawValue: typeValue), type == .ended else {
                return
            }
            self?.scheduleRestart(reason: "interruption ended")
        }))
        self.observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: AVAudioSession.sharedInstance(), queue: .main, using: { [weak self] _ in
            self?.scheduleRestart(reason: "media services reset")
        }))
    }
    
    /// Safe to call from any queue and as often as the setting changes.
    func update(enabled: Bool) {
        Queue.mainQueue().async {
            self.setUpObserversIfNeeded()
            if enabled == self.isEnabled {
                return
            }
            self.isEnabled = enabled
            if enabled {
                self.start()
            } else {
                self.stop()
            }
        }
    }
    
    private func updateAppActive(_ isActive: Bool) {
        if self.isAppActive == isActive {
            return
        }
        self.isAppActive = isActive
        self.updatePlayback()
    }
    
    private func start() {
        Logger.shared.log("KeepAlive", "enabled")
        self.pushSession()
    }
    
    private func stop() {
        Logger.shared.log("KeepAlive", "disabled")
        self.restartTimer?.invalidate()
        self.restartTimer = nil
        self.sessionDisposable?.dispose()
        self.sessionDisposable = nil
        self.hasSession = false
        self.updatePlayback()
    }
    
    /// The holder stays pushed while the setting is on, beneath everything else, so a voice message or music
    /// started later takes over and hands the session back. Pushing it only on the way to the background would
    /// put it on top and pause whatever is already playing.
    private func pushSession() {
        self.sessionDisposable?.dispose()
        self.hasSession = false
        self.sessionDisposable = MediaManagerImpl.globalAudioSession.push(audioSessionType: .play(mixWithOthers: true), activate: { [weak self] _ in
            Queue.mainQueue().async {
                guard let self else {
                    return
                }
                self.hasSession = true
                self.updatePlayback()
            }
        }, deactivate: { [weak self] _ in
            return Signal { subscriber in
                Queue.mainQueue().async {
                    if let self {
                        self.hasSession = false
                        self.updatePlayback()
                    }
                    subscriber.putCompletion()
                }
                return EmptyDisposable
            }
        })
    }
    
    private func scheduleRestart(reason: String) {
        guard self.isEnabled else {
            return
        }
        self.restartTimer?.invalidate()
        // The session cannot be taken back the instant an interruption ends; give the other side a moment.
        let timer = SwiftSignalKit.Timer(timeout: 1.0, repeat: false, completion: { [weak self] in
            guard let self, self.isEnabled else {
                return
            }
            self.restartTimer = nil
            Logger.shared.log("KeepAlive", "restarting after \(reason)")
            self.endPlayback()
            self.pushSession()
        }, queue: Queue.mainQueue())
        self.restartTimer = timer
        timer.start()
    }
    
    private func updatePlayback() {
        if self.isEnabled && self.hasSession && !self.isAppActive {
            self.beginPlayback()
        } else {
            self.endPlayback()
        }
    }
    
    private func beginPlayback() {
        if let player = self.player {
            if !player.isPlaying && !player.play() {
                Logger.shared.log("KeepAlive", "silent loop refused to resume")
            }
            return
        }
        do {
            let player = try AVAudioPlayer(data: silentWaveData())
            player.numberOfLoops = -1
            player.volume = 0.0
            player.prepareToPlay()
            if player.play() {
                self.player = player
                Logger.shared.log("KeepAlive", "silent loop started")
            } else {
                Logger.shared.log("KeepAlive", "silent loop refused to start")
            }
        } catch {
            Logger.shared.log("KeepAlive", "silent loop failed: \(error)")
        }
    }
    
    private func endPlayback() {
        if let player = self.player {
            player.stop()
            self.player = nil
            Logger.shared.log("KeepAlive", "silent loop stopped")
        }
    }
}

/// One second of 8 kHz, 16-bit mono PCM silence in a WAV container.
private func silentWaveData() -> Data {
    let sampleRate: UInt32 = 8000
    let dataSize: UInt32 = sampleRate * 2
    var data = Data()
    func append32(_ value: UInt32) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
    func append16(_ value: UInt16) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
    data.append(contentsOf: Array("RIFF".utf8))
    append32(36 + dataSize)
    data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8))
    append32(16)
    append16(1)
    append16(1)
    append32(sampleRate)
    append32(sampleRate * 2)
    append16(2)
    append16(16)
    data.append(contentsOf: Array("data".utf8))
    append32(dataSize)
    data.append(Data(count: Int(dataSize)))
    return data
}
