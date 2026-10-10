import Foundation
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
    
    private init() {
    }
    
    /// Safe to call from any queue and as often as the setting changes.
    func update(enabled: Bool) {
        Queue.mainQueue().async {
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
    
    private func start() {
        Logger.shared.log("KeepAlive", "enabled")
        self.sessionDisposable?.dispose()
        self.sessionDisposable = MediaManagerImpl.globalAudioSession.push(audioSessionType: .play(mixWithOthers: true), activate: { [weak self] _ in
            Queue.mainQueue().async {
                self?.beginPlayback()
            }
        }, deactivate: { [weak self] _ in
            return Signal { subscriber in
                Queue.mainQueue().async {
                    self?.endPlayback()
                    subscriber.putCompletion()
                }
                return EmptyDisposable
            }
        })
    }
    
    private func stop() {
        Logger.shared.log("KeepAlive", "disabled")
        self.sessionDisposable?.dispose()
        self.sessionDisposable = nil
        self.endPlayback()
    }
    
    private func beginPlayback() {
        guard self.isEnabled, self.player == nil else {
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
