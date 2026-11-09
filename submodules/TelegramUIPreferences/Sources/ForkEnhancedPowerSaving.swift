import Foundation
import SwiftSignalKit
import TelegramCore

/// Donutgram's Enhanced Power Saving. Each value stays where its own screen keeps it (Power Saving, Reduce Motion in
/// Appearance, the Extras switches), so all three are written in one transaction together with the snapshot: a crash
/// can't leave the animations off with nothing to restore them from. Telegram's own automatic power saving (the
/// battery threshold) and iOS Low Power Mode only override these at runtime, so they keep working on top of this.
/// Message effects have no setting of their own; they stop playing by themselves while `enhancedPowerSaving` is on.
public func setForkEnhancedPowerSaving(accountManager: AccountManager<TelegramAccountManagerTypes>, enabled: Bool) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        var extras = transaction.getSharedData(ApplicationSpecificSharedDataKeys.forkExtrasSettings)?.get(ForkExtrasSettings.self) ?? .defaultSettings
        var media = transaction.getSharedData(ApplicationSpecificSharedDataKeys.automaticMediaDownloadSettings)?.get(MediaAutoDownloadSettings.self) ?? .defaultSettings
        var theme = transaction.getSharedData(ApplicationSpecificSharedDataKeys.presentationThemeSettings)?.get(PresentationThemeSettings.self) ?? .defaultSettings

        if enabled {
            if extras.enhancedPowerSaving {
                return
            }
            extras.enhancedPowerSavingSnapshot = ForkPowerSavingSnapshot(
                autoplayVideo: media.energyUsageSettings.autoplayVideo,
                autoplayGif: media.energyUsageSettings.autoplayGif,
                loopStickers: media.energyUsageSettings.loopStickers,
                loopEmoji: media.energyUsageSettings.loopEmoji,
                fullTranslucency: media.energyUsageSettings.fullTranslucency,
                reduceMotion: theme.reduceMotion,
                snowEnabled: extras.snowEnabled,
                avatarGlowEnabled: extras.avatarGlowEnabled,
                reactionGlowEnabled: extras.reactionGlowEnabled
            )
            extras.enhancedPowerSaving = true
            media.energyUsageSettings.autoplayVideo = false
            media.energyUsageSettings.autoplayGif = false
            media.energyUsageSettings.loopStickers = false
            media.energyUsageSettings.loopEmoji = false
            media.energyUsageSettings.fullTranslucency = false
            // Reduce Motion stops the wallpaper's gradient from moving when a message is sent.
            theme.reduceMotion = true
            extras.snowEnabled = false
            extras.avatarGlowEnabled = false
            extras.reactionGlowEnabled = false
        } else {
            if !extras.enhancedPowerSaving {
                return
            }
            if let snapshot = extras.enhancedPowerSavingSnapshot {
                media.energyUsageSettings.autoplayVideo = snapshot.autoplayVideo
                media.energyUsageSettings.autoplayGif = snapshot.autoplayGif
                media.energyUsageSettings.loopStickers = snapshot.loopStickers
                media.energyUsageSettings.loopEmoji = snapshot.loopEmoji
                media.energyUsageSettings.fullTranslucency = snapshot.fullTranslucency
                theme.reduceMotion = snapshot.reduceMotion
                extras.snowEnabled = snapshot.snowEnabled
                extras.avatarGlowEnabled = snapshot.avatarGlowEnabled
                extras.reactionGlowEnabled = snapshot.reactionGlowEnabled
            }
            extras.enhancedPowerSaving = false
            extras.enhancedPowerSavingSnapshot = nil
        }

        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.forkExtrasSettings, { _ in
            return SharedPreferencesEntry(extras)
        })
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.automaticMediaDownloadSettings, { _ in
            return EnginePreferencesEntry(media)
        })
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.presentationThemeSettings, { _ in
            return EnginePreferencesEntry(theme)
        })
    }
}
