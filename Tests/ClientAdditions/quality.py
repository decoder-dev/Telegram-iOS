"""Execute UI failure/retry paths extracted from production sources; no iOS SDK required."""
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
KEEP = 'submodules/TelegramUI/Sources/ForkBackgroundKeepAlive.swift'
ICON = 'submodules/SettingsUI/Sources/Themes/ThemeSettingsController.swift'
CONTENT = 'submodules/TelegramCore/Sources/Settings/ContentSettings.swift'
SWITCH = 'submodules/Display/Source/SwitchNode.swift'

def read(path):
    return (ROOT / path).read_text(encoding='utf-8')

def method(path, marker, indent=''):
    text = read(path)
    start = text.index(marker)
    return text[start:text.index('\n'+indent+'}', start)+len(indent)+2]

class Contracts(unittest.TestCase):
    def test_sensitive_content_has_one_home_and_old_links_redirect(self):
        source = read('submodules/SettingsUI/Sources/Data and Storage/DataAndStorageSettingsController.swift')
        self.assertNotIn('entries.append(.sensitiveContent(', source)
        self.assertIn('case .sensitiveContent?: return forkExtrasController(context: context, focus: .messageFilters, focusItemId: 147)', source)
        extras = read('submodules/SettingsUI/Sources/ForkExtrasController.swift')
        self.assertIn('.settingToggle(147, .messageFilters, ForkExtrasLocalizedString.showSensitiveContent, settings.showSensitiveContent, \\.showSensitiveContent)', extras)
        self.assertIn('forkExtrasSettings(accountManager:', extras)
    def test_audio_play_label_exists_in_the_real_catalog(self):
        source = read('submodules/TelegramUI/Components/AttachmentFileController/Sources/AttachmentFileController.swift')
        key = re.search(r'ContextMenuActionItem\(text: presentationData.strings.(\w+), icon:.*Context Menu/Play', source).group(1)
        self.assertIn('"'+key.replace('_','.')+'" =', read('Telegram/Telegram-iOS/en.lproj/Localizable.strings'))
        self.assertNotIn('ContextMenuActionItem(text: "Play",', source)
    def test_summary_cancels_and_suppresses_stale_results(self):
        worker = read('submodules/TelegramUI/Sources/ForkOnDeviceAI.swift')
        ui = read('submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift')
        self.assertIn('guard !self.inProgress.swap(true)', worker)
        self.assertIn('task.cancel()', worker)
        self.assertIn('try Task.checkCancellation()', worker)
        self.assertIn('guard !cancelled.with({ $0 })', worker)
        self.assertIn('OverlayStatusController(theme:', ui)
        self.assertIn('ForkOnDeviceAI.summarize(messageText)\n                |> deliverOnMainQueue', ui)
    def test_network_reacts_to_actual_keep_alive_state(self):
        self.assertIn('player?.isPlaying == true', read(KEEP))
        self.assertIn('keepsNetworkAlivePromise.get()', read('submodules/TelegramUI/Sources/SharedWakeupManager.swift'))


def swift_tests():
    policy = method(KEEP, 'struct ForkKeepAliveRetryPolicy {')
    resolver = method(CONTENT, 'func forkContentRestrictionReasons(')
    functions = '\n'.join(method(KEEP, '    private func '+name+'(', '    ').replace('private func', 'func', 1) for name in ['updatePlayback','schedulePlaybackRetry','beginPlayback','endPlayback'])
    property_source = method(KEEP, '    var keepsNetworkAlive: Bool {', '    ')
    icon_source = read(ICON)
    a = icon_source.index('        guard !appIconChangeInProgress else { return }')
    b = icon_source.index('\n    }, editTheme:', a)
    icon_apply = icon_source[a:b]
    handle_update = method(SWITCH, '    private func updateHandleColor()', '    ').replace('private func','func',1)
    fixture = r"""
import Foundation
class Queue { static func mainQueue() -> Queue { Queue() }; func async(_ f: () -> Void) { f() } }
class Promise<T> { var value: T; init(_ value: T) { self.value=value }; func set(_ value: T) { self.value=value } }
class Logger { static let shared=Logger(); func log(_ a: String,_ b: String) {} }
enum SwiftSignalKit {
    class Timer {
        static var created: [Timer] = []
        let timeout: Double; let completion: () -> Void; var active=true
        init(timeout: Double, repeat: Bool, completion: @escaping () -> Void, queue: Queue) {
            self.timeout=timeout; self.completion=completion; Self.created.append(self)
        }
        func start() {}; func invalidate() { active=false }; func fire() { if active { active=false; completion() } }
    }
}
class AVAudioPlayer {
    static var results: [Bool]=[]; static var plays=0
    var isPlaying=false; var volume=0.0; var numberOfLoops=0
    init(data: Data) throws {}
    func prepareToPlay() {}
    func play() -> Bool { Self.plays+=1; isPlaying=Self.results.isEmpty ? true : Self.results.removeFirst(); return isPlaying }
    func stop() { isPlaying=false }
}
func silentWaveData() -> Data { Data() }
enum ForkSensitiveContentSettings { static let liftedReasons: Set<String>=["porn","sensitive"] }
__POLICY__
__RESOLVER__
class KeepHarness {
    var retryPolicy=ForkKeepAliveRetryPolicy(); var isEnabled=true; var hasSession=true; var isAppActive=false
    var restartTimer: SwiftSignalKit.Timer?; var sessionGeneration=0; var player: AVAudioPlayer?
    let keepsNetworkAlivePromise=Promise(false)
__PROPERTY__
__METHODS__
}
AVAudioPlayer.results=[false,false,false,false]
let keep=KeepHarness(); keep.updatePlayback()
precondition(!keep.keepsNetworkAlive && !keep.keepsNetworkAlivePromise.value)
let firstRetry=keep.restartTimer!
keep.updatePlayback(); keep.updatePlayback()
precondition(AVAudioPlayer.plays == 1 && keep.restartTimer === firstRetry, "Repeated updates must not bypass backoff")
for delay in [1.0,2.0,4.0] { precondition(keep.restartTimer?.timeout == delay); keep.restartTimer!.fire() }
precondition(keep.restartTimer == nil && AVAudioPlayer.plays == 4, "Recovery must stop after four failed attempts")
keep.isAppActive=true; keep.updatePlayback(); keep.isAppActive=false
AVAudioPlayer.results=[false,true]; keep.updatePlayback(); keep.restartTimer!.fire()
precondition(keep.player?.isPlaying == true && keep.keepsNetworkAlivePromise.value)
precondition(keep.retryPolicy.attempts == 0)
keep.player!.stop(); AVAudioPlayer.results=[false]; keep.updatePlayback()
let pending=keep.restartTimer!; let before=AVAudioPlayer.plays
keep.isEnabled=false; keep.updatePlayback(); pending.fire()
precondition(AVAudioPlayer.plays == before && keep.restartTimer == nil && !keep.keepsNetworkAlive)
let owner=KeepHarness(); AVAudioPlayer.results=[false]; owner.updatePlayback(); let ownerTimer=owner.restartTimer!
owner.hasSession=false; owner.updatePlayback(); let ownerPlays=AVAudioPlayer.plays; ownerTimer.fire()
precondition(AVAudioPlayer.plays == ownerPlays, "Do not steal another audio holder's session")
for reasons: Set<String> in [[], ["porn"], ["porn","sensitive","other"], ["other"]] {
    precondition(forkContentRestrictionReasons(serverReasons: reasons, showSensitiveContent: false) == reasons.subtracting(["porn","sensitive"]))
    precondition(forkContentRestrictionReasons(serverReasons: reasons, showSensitiveContent: true) == reasons.union(["porn","sensitive"]))
}
struct Icon { var name: String; var isDefault: Bool }
class Bindings {
    var actual: String?; var completion: ((Bool) -> Void)?; var calls=0
    func getAlternateIconName() -> String? { actual }
    func requestSetAlternateIconName(_ name: String?,_ callback: @escaping (Bool) -> Void) { calls+=1; completion=callback }
}
struct Strings { let Common_OK="OK" }; struct Presentation { let strings=Strings() }
struct AtomicValue { func with<T>(_ f: (Presentation) -> T) -> T { f(Presentation()) } }
class Shared { let applicationBindings=Bindings(); let currentPresentationData=AtomicValue() }
class Context { let sharedContext=Shared() }
enum ForkPresentationLanguage { static let prefersRussianStrings=false }
struct TextAlertAction { enum Kind { case defaultAction }; init(type: Kind,title: String,action: () -> Void) {} }
func textAlertController(context: Context,title: String?,text: String,actions: [TextAlertAction]) -> Int { 0 }
let context=Context(); let appIcons=[Icon(name: "BlueIcon",isDefault:true),Icon(name: "BlackIcon",isDefault:false)]
var appIconChangeInProgress=false; let currentAppIconName=Promise<String?>("BlueIcon"); var errors=0
let presentControllerImpl: ((Int,Any?) -> Void)? = { _,_ in errors+=1 }
func applyIcon(_ icon: Icon) {
__ICON_APPLY__
}
applyIcon(appIcons[1]); applyIcon(appIcons[0])
precondition(context.sharedContext.applicationBindings.calls == 1 && currentAppIconName.value == "BlueIcon")
context.sharedContext.applicationBindings.completion!(false)
precondition(!appIconChangeInProgress && currentAppIconName.value == "BlueIcon" && errors == 1)
applyIcon(appIcons[1]); context.sharedContext.applicationBindings.actual="BlackIcon"
context.sharedContext.applicationBindings.completion!(true)
precondition(currentAppIconName.value == "BlackIcon" && errors == 1)
class UISwitch { var thumbTintColor: Int? }
class SwitchHarness {
    var isNodeLoaded=false; var view=UISwitch(); var _isOn=false; var handleColor=7
__HANDLE_UPDATE__
}
let thumb=SwitchHarness(); thumb.updateHandleColor(); precondition(thumb.view.thumbTintColor == nil)
thumb.isNodeLoaded=true; thumb._isOn=true; thumb.updateHandleColor(); precondition(thumb.view.thumbTintColor == 7)
thumb.handleColor=9; thumb.updateHandleColor(); precondition(thumb.view.thumbTintColor == 9)
thumb._isOn=false; thumb.updateHandleColor(); precondition(thumb.view.thumbTintColor == nil)
print("KeepAlive failure/success/disable/ownership; content choices; icon errors/overlap/success; thumb states passed")
"""
    for token,source in [('POLICY',policy),('RESOLVER',resolver),('PROPERTY',property_source),('METHODS',functions),('ICON_APPLY',icon_apply),('HANDLE_UPDATE',handle_update)]:
        fixture=fixture.replace('__'+token+'__',source)
    with tempfile.TemporaryDirectory(prefix='banana-quality-') as tmp:
        path=pathlib.Path(tmp)/'main.swift'; path.write_text(fixture,encoding='utf-8')
        subprocess.run(['swift',str(path)],check=True,timeout=120)
        for path in [KEEP,ICON,CONTENT,SWITCH,'submodules/TelegramUI/Sources/ForkOnDeviceAI.swift',
                     'submodules/TelegramUI/Sources/SharedWakeupManager.swift',
                     'submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift',
                     'submodules/TelegramUI/Components/AttachmentFileController/Sources/AttachmentFileController.swift',
                     'submodules/SettingsUI/Sources/Data and Storage/DataAndStorageSettingsController.swift']:
            subprocess.run(['swiftc','-frontend','-parse',str(ROOT/path)],check=True,timeout=120)

if __name__ == '__main__':
    result=unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(Contracts))
    if not result.wasSuccessful(): sys.exit(1)
    if '--structural-only' not in sys.argv: swift_tests()
