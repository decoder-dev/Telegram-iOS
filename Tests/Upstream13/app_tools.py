"""App-level tools: settings backup, GitHub update check, reset on next launch (Settings.bundle), data center latency
on Connection Check and Enhanced Power Saving. Source-text checks; the Swift is verified by the full Bazel build."""
import pathlib
import plistlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
POWER = 'submodules/TelegramUIPreferences/Sources/ForkEnhancedPowerSaving.swift'
RESET = 'submodules/TelegramUIPreferences/Sources/ForkLocalDataReset.swift'
EXTRAS = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
ABOUT = 'submodules/SettingsUI/Sources/BananaAboutController.swift'
BACKUP = 'submodules/SettingsUI/Sources/BananaSettingsBackup.swift'
UPDATES = 'submodules/SettingsUI/Sources/BananaUpdateCheck.swift'
STATUS = 'submodules/SettingsUI/Sources/Data and Storage/ProxyConnectionStatusController.swift'
APP_DELEGATE = 'submodules/TelegramUI/Sources/AppDelegate.swift'
ITEM_VIEW = 'submodules/TelegramUI/Components/Chat/ChatMessageItemView/Sources/ChatMessageItemView.swift'
BUNDLE = 'Telegram/Telegram-iOS/Settings.bundle'

FIELDS = [
    ('updateCheckIncludesPrereleases', 'Bool', 'true'),
    ('updateCheckAutomatically', 'Bool', 'false'),
    ('enhancedPowerSaving', 'Bool', 'false'),
]


def read(name):
    return (ROOT / name).read_text(encoding='utf-8')


class Settings(unittest.TestCase):
    def test_fields_are_declared_defaulted_decoded_and_encoded(self):
        source = read(SETTINGS)
        for name, kind, default in FIELDS:
            with self.subTest(name=name):
                self.assertIn('    public var %s: %s\n' % (name, kind), source)
                self.assertIn('        self.%s = %s\n' % (name, default), source)
                self.assertIn('self.%s = try container.decodeIfPresent(%s.self, forKey: "%s") ?? %s' % (name, kind, name, default), source)
                self.assertIn('try container.encode(self.%s, forKey: "%s")' % (name, name), source)

    def test_snapshot_round_trips_and_a_bad_one_costs_nothing_else(self):
        source = read(SETTINGS)
        self.assertIn('    public var enhancedPowerSavingSnapshot: ForkPowerSavingSnapshot?\n', source)
        self.assertIn('        self.enhancedPowerSavingSnapshot = nil\n', source)
        self.assertIn('self.enhancedPowerSavingSnapshot = try? container.decodeIfPresent(ForkPowerSavingSnapshot.self, forKey: "enhancedPowerSavingSnapshot")', source)
        self.assertIn('try container.encodeIfPresent(self.enhancedPowerSavingSnapshot, forKey: "enhancedPowerSavingSnapshot")', source)


class EnhancedPowerSaving(unittest.TestCase):
    def test_on_saves_then_turns_off_and_off_restores_in_one_transaction(self):
        source = read(POWER)
        body = source[source.index('public func setForkEnhancedPowerSaving('):]
        on = body[body.index('        if enabled {'):body.index('        } else {')]
        off = body[body.index('        } else {'):body.index('        transaction.updateSharedData(')]
        # The snapshot is taken before anything is changed.
        self.assertLess(on.index('extras.enhancedPowerSavingSnapshot = ForkPowerSavingSnapshot('), on.index('media.energyUsageSettings.loopStickers = false'))
        for name in ['autoplayVideo', 'autoplayGif', 'loopStickers', 'loopEmoji', 'fullTranslucency']:
            self.assertIn('media.energyUsageSettings.%s = false' % name, on)
            self.assertIn('media.energyUsageSettings.%s = snapshot.%s' % (name, name), off)
        for name in ['snowEnabled', 'avatarGlowEnabled', 'reactionGlowEnabled']:
            self.assertIn('extras.%s = false' % name, on)
            self.assertIn('extras.%s = snapshot.%s' % (name, name), off)
        self.assertIn('theme.reduceMotion = true', on)
        self.assertIn('theme.reduceMotion = snapshot.reduceMotion', off)
        self.assertIn('extras.enhancedPowerSavingSnapshot = nil', off)
        # Turning it on twice must not overwrite the saved values with the reduced ones.
        self.assertIn('if extras.enhancedPowerSaving {\n                return\n            }', on)
        # The battery threshold is the user's: never part of the snapshot.
        self.assertNotIn('activationThreshold', body)
        for key in ['forkExtrasSettings', 'automaticMediaDownloadSettings', 'presentationThemeSettings']:
            self.assertIn('transaction.updateSharedData(ApplicationSpecificSharedDataKeys.%s' % key, body)

    def test_switch_lives_on_media_and_goes_through_the_setter(self):
        source = read(EXTRAS)
        self.assertIn('.appearanceToggle(2381, russian ? "Усиленное энергосбережение" : "Enhanced Power Saving", settings.enhancedPowerSaving, \\.enhancedPowerSaving)', source)
        media = re.search(r'\(\.media, \[(.*?)\]\),\n', source, re.S).group(1)
        self.assertIn('[2381, 2382]', media)
        self.assertIn('if keyPath == \\ForkExtrasSettings.enhancedPowerSaving {\n                updateDisposable.set(setForkEnhancedPowerSaving(accountManager: context.sharedContext.accountManager, enabled: value).start())\n                return\n            }', source)

    def test_message_effects_only_play_when_tapped(self):
        source = read(ITEM_VIEW)
        self.assertIn('if !force, let item = self.item, item.context.sharedContext.immediateForkExtrasSettings.enhancedPowerSaving {\n            return\n        }', source)
        self.assertIn('"//submodules/TelegramUIPreferences",', read('submodules/TelegramUI/Components/Chat/ChatMessageItemView/BUILD'))


class Backup(unittest.TestCase):
    def test_secrets_and_device_bound_values_never_travel(self):
        source = read(BACKUP)
        for key in ['localVerificationBadges', 'localVerificationBadgesIds', 'localVerificationBadgesValues', 'duressPasscodeAction', 'duressLogOutAccountIds', 'enhancedPowerSaving', 'enhancedPowerSavingSnapshot', 'sessionKeychainBackup']:
            self.assertIn('"%s",' % key, source)
        self.assertIn('lowercased.contains("apikey") || lowercased.contains("token") || lowercased.contains("password")', source)
        # Excluded both when writing and when reading.
        self.assertIn('for key in object.keys where isExcluded(key)', source)
        self.assertIn('return values.filter { !isExcluded($0.key) }', source)

    def test_nothing_that_looks_secret_is_exported(self):
        # A key, a token or a password added to the settings later is caught by name; the switches named so are plain settings.
        excluded = {'localVerificationBadges', 'localVerificationBadgesIds', 'localVerificationBadgesValues', 'duressPasscodeAction', 'duressLogOutAccountIds', 'enhancedPowerSaving', 'enhancedPowerSavingSnapshot', 'sessionKeychainBackup'}
        for key in set(re.findall(r'forKey: "(\w+)"', read(SETTINGS))):
            lower = key.lower()
            if key in ('allowSecretScreenshots', 'sendWithReturnKey') or not any(word in lower for word in ['key', 'secret', 'token', 'password']):
                continue
            with self.subTest(key=key):
                self.assertTrue(key in excluded or 'apikey' in lower or 'token' in lower or 'password' in lower, key)

    def test_header_and_tolerant_import(self):
        source = read(BACKUP)
        for key in ['"app": appName', '"version":', '"build":', '"exportedAt":', '"settings": object']:
            self.assertIn(key, source)
        self.assertIn('for (key, value) in values where known.contains(key)', source)
        self.assertIn('options: [.prettyPrinted, .sortedKeys]', source)

    def test_import_previews_and_applies_through_the_shared_settings(self):
        source = read(ABOUT)
        self.assertIn('BananaAboutStrings.changeCount(count)', source)
        self.assertIn('updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in\n                            return BananaSettingsBackup.apply(values, to: current)', source)
        self.assertIn('forkExtrasPresentNativeController(activity, context: context)', source)


class Updates(unittest.TestCase):
    def test_build_number_comes_from_the_tag_and_cfbundleversion(self):
        source = read(UPDATES)
        self.assertIn('https://api.github.com/repos/decoder-dev/Telegram-iOS/releases', source)
        self.assertIn('Bundle.main.infoDictionary?["CFBundleVersion"]', source)
        self.assertIn('return tag.split(separator: "-").reversed().compactMap({ Int($0) }).first', source)
        self.assertIn('if !includePrereleases && release["prerelease"] as? Bool == true', source)
        self.assertIn('"SHA256SUMS.txt"', source)
        self.assertIn('URLSessionConfiguration.ephemeral', source)
        self.assertIn('"User-Agent": "BananaGram"', source)
        # The workflow still tags releases with the build number CFBundleVersion gets.
        workflow = read('.github/workflows/build.yml')
        self.assertIn('TAG="v${APP_VERSION}-${BUILD_NUMBER}-pre"', workflow)
        self.assertIn('--buildNumber="$BUILD_NUMBER"', workflow)
        self.assertIn('sha256sum "$IPA_NAME" > SHA256SUMS.txt', workflow)

    def test_tag_parsing(self):
        def build(tag):
            for part in reversed(tag.split('-')):
                if part.isdigit():
                    return int(part)
            return None
        self.assertEqual(build('v13.1.2-4511-pre'), 4511)
        self.assertEqual(build('v13.1.2-4511'), 4511)
        self.assertIsNone(build('v13.1.2'))

    def test_automatic_check_is_daily_and_off_by_default(self):
        source = read(UPDATES)
        self.assertIn('guard settings.updateCheckAutomatically else', source)
        self.assertIn('now < lastCheck + 24.0 * 60.0 * 60.0', source)
        self.assertIn('bananaCheckForUpdatesAutomatically(sharedContext: sharedApplicationContext.sharedContext)', read(APP_DELEGATE))

    def test_about_is_reachable_from_the_hub(self):
        source = read(EXTRAS)
        self.assertIn('.destination(2380, ForkPresentationLanguage.prefersRussianStrings ? "О BananaGram" : "About BananaGram", .about)', source)
        self.assertIn('case .about: pushControllerImpl?(bananaAboutController(context: context))', source)
        about = read(ABOUT)
        ids = [int(value) for value in re.findall(r'case \.\w+: return (\d+)', about)]
        self.assertTrue(ids and all(2380 <= value <= 2419 for value in ids))
        self.assertEqual(ids, sorted(ids))


class LocalDataReset(unittest.TestCase):
    def test_settings_bundle_switches_match_the_launch_keys(self):
        plist = plistlib.loads((ROOT / BUNDLE / 'Root.plist').read_bytes())
        keys = [item.get('Key') for item in plist['PreferenceSpecifiers'] if item['Type'] == 'PSToggleSwitchSpecifier']
        self.assertEqual(keys, ['BananaResetCacheOnNextLaunch', 'BananaResetDatabaseOnNextLaunch'])
        source = read(RESET)
        self.assertIn('public static let resetCacheKey = "BananaResetCacheOnNextLaunch"', source)
        self.assertIn('public static let resetDatabaseKey = "BananaResetDatabaseOnNextLaunch"', source)
        for language in ['en', 'ru']:
            strings = (ROOT / BUNDLE / ('%s.lproj' % language) / 'Root.strings').read_text(encoding='utf-8')
            for item in plist['PreferenceSpecifiers']:
                self.assertIn('"%s" =' % item['Title'], strings)

    def test_bundle_is_part_of_the_app(self):
        build = read('Telegram/BUILD')
        self.assertIn('bundle_imports = glob(["Telegram-iOS/Settings.bundle/**"]),', build)
        self.assertIn('settings_bundle = ":SettingsBundle",', build)
        self.assertIn('"apple_bundle_import",', build)

    def test_flags_are_cleared_first_and_only_cache_and_db_go(self):
        source = read(RESET)
        body = source[source.index('public static func performIfRequested('):]
        self.assertLess(body.index('self.isDatabaseResetRequested = false'), body.index('removeItem'))
        removed = re.findall(r'removeItem\(atPath: postboxPath \+ "(/\w+)"\)', body)
        self.assertEqual(sorted(removed), ['/db', '/media'])
        self.assertIn('if resetDatabase && record.hasKeys {', body)
        self.assertNotIn('accounts-metadata"', body)

    def test_reset_runs_before_any_postbox_opens(self):
        source = read(APP_DELEGATE)
        reset = source.index('ForkLocalDataReset.performIfRequested(accountManager: accountManager, rootPath: rootPath)')
        self.assertLess(source.index('let accountManager: AccountManager<TelegramAccountManagerTypes> = setupAccountManager('), reset)
        self.assertLess(reset, source.index('let sharedContext = SharedAccountContextImpl('))


class DatacenterLatency(unittest.TestCase):
    def test_connection_check_pings_each_datacenter_with_mtproto(self):
        source = read(STATUS)
        self.assertIn('MTProxyConnectivity.pingProxy(with: network.context, datacenterId: datacenterId, settings: network.context.apiEnvironment.socksProxySettings)', source)
        self.assertIn('let ids = network.context.isTestingEnvironment ? [1, 2, 3] : [1, 2, 3, 4, 5]', source)
        self.assertIn('if case .web = proxySettings.effectiveActiveServer?.connection {', source)
        self.assertIn('network: context.account.network))', read(EXTRAS))
        self.assertIn('connectionStatus: network.connectionStatus, network: network))', read('submodules/SettingsUI/Sources/Data and Storage/ProxyListSettingsController.swift'))


if __name__ == '__main__':
    unittest.main()
