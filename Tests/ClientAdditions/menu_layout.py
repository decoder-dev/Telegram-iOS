"""Check the real Extras entry factory and legacy routes after menu consolidation."""
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
EXTRAS = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
def read(name): return (ROOT/name).read_text(encoding='utf-8')
def declaration(text, marker):
    start=text.index(marker)
    return text[start:text.index('\n}',start)+2]
class Placement(unittest.TestCase):
    def test_main_menu_has_one_fork_entry(self):
        source=read('submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift')
        self.assertEqual(source.count('interaction.openSettings(.forkExtras)'),1)
        self.assertNotIn('interaction.openSettings(.appearance)',source)
        self.assertNotIn('interaction.openSettings(.debug)',source)
        extras=read(EXTRAS)
        for destination in ['themeSettingsController(context: context)','makeProxySettingsController(context: context)','makeDebugSettingsController(context: context)','archiveSettingsController(context: context)']:
            self.assertIn(destination,extras)
    def test_no_duplicate_controls(self):
        data=read('submodules/SettingsUI/Sources/Data and Storage/DataAndStorageSettingsController.swift')
        for row in ['pauseMusicOnRecording','pauseMusicOnVoiceRecording','pauseMusicOnVoicePlayback','sensitiveContent','connectionProxy']:
            self.assertNotIn('entries.append(.'+row+'(',data)
        theme=read('submodules/SettingsUI/Sources/Themes/ThemeSettingsController.swift')
        self.assertNotIn('entries.append(.useRecentEmojiInReactions(',theme)
        factory=declaration(read(EXTRAS),'private func forkExtrasControllerEntries(')
        self.assertNotIn('.brandTheme(',factory)
        self.assertNotIn('.autoFetchMtProxy(',factory)
        self.assertEqual(factory.count('settings.useRecentEmojiInReactions'),1)
    def test_legacy_links_and_search_point_at_visible_rows(self):
        data=read('submodules/SettingsUI/Sources/Data and Storage/DataAndStorageSettingsController.swift')
        for tag,item in [('pauseMusicOnRecording',2001),('pauseMusicOnVoiceRecording',2002),('pauseMusicOnVoicePlayback',2003),('sensitiveContent',147)]:
            self.assertRegex(data,r'case \.'+tag+r'\?: return forkExtrasController\([^\n]+focusItemId: '+str(item)+r'\)')
        theme=read('submodules/SettingsUI/Sources/Themes/ThemeSettingsController.swift')
        self.assertIn('focus: .interface, focusItemId: 1521',theme)
        search=read('submodules/SettingsUI/Sources/Search/SettingsSearchableItems.swift')
        for item in [2001,2002,2003,147,1521]:
            self.assertIn('focusItemId: '+str(item),search)
        self.assertIn('focus == .network && focusItemId == 142',read(EXTRAS))
    def test_music_reads_and_writes_original_store(self):
        source=read(EXTRAS)
        self.assertIn('ApplicationSpecificSharedDataKeys.mediaInputSettings',source)
        self.assertIn('?.get(MediaInputSettings.self) ?? .defaultSettings',source)
        self.assertIn('updateMediaInputSettingsInteractively(',source)
        self.assertIn('case 2002: return current.withUpdatedVoiceMusicPolicy(recording: value)',source)
        self.assertIn('case 2003: return current.withUpdatedVoiceMusicPolicy(playback: value)',source)

def swift_tests():
    source=read(EXTRAS)
    prefs=read('submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift')
    prefs=prefs[:prefs.index('/// Last opened chat-list folder.')]
    for module in ['TelegramCore','SwiftSignalKit','Postbox']:
        prefs=prefs.replace('import '+module+'\n','')
    media=declaration(read('submodules/TelegramUIPreferences/Sources/MediaInputSettings.swift'),'public struct MediaInputSettings:')
    entry=source[source.index('private enum ForkExtrasEntry:'):source.index('    func item(presentationData:',source.index('private enum ForkExtrasEntry:'))]+'}\n'
    entry=entry.replace(': ItemListNodeEntry {',': Equatable, Comparable {',1)
    factory=declaration(source,'private func forkExtrasControllerEntries(')
    focus=declaration(source,'public enum ForkExtrasControllerFocus {')
    localized=set(re.findall(r'ForkExtrasLocalizedString\.([A-Za-z_]+)',factory+focus))-{'string'}
    stubs="""
import Foundation
public struct StringCodingKey: CodingKey, ExpressibleByStringLiteral {
 public var stringValue: String; public var intValue: Int? { nil }
 public init(stringValue: String) { self.stringValue=stringValue }
 public init?(intValue: Int) { return nil }
 public init(stringLiteral value: String) { self.stringValue=value }
}
public enum MessageSavingBridge { public static let defaultDeletedMark="deleted" }
enum ForkPresentationLanguage { static var prefersRussianStrings=false }
typealias ItemListSectionId=Int32
class UIDevice { enum Idiom { case phone,pad }; static let current=UIDevice(); var userInterfaceIdiom=Idiom.phone }
struct BananaTabBarLayout: Equatable { let hidden: Bool; let contacts: Bool; let calls: Bool; let wide: Bool; let integratedSearch: Bool; let searchOnLeft: Bool }
enum ForkExtrasHotFlags { static func hidesTabBar(_ value: Bool,isPad: Bool) -> Bool { value && !isPad } }
enum ForkRegexMessageFilters { static func unusablePatternCount(_ patterns: [String]) -> Int { 0 } }
"""
    stubs+='enum ForkExtrasLocalizedString { static func string(forKey key: String) -> String { key }\n'+'\n'.join('static let '+name+'="'+name+'"' for name in sorted(localized))+'\n}\n'
    defs='\n'.join([declaration(source,'private enum ForkExtrasDestination:'),declaration(source,'private enum ForkExtrasSection:'),focus,entry,factory])
    tests=r"""
for russian in [false,true] {
 ForkPresentationLanguage.prefersRussianStrings=russian
 for idiom in [UIDevice.Idiom.phone,.pad] {
  UIDevice.current.userInterfaceIdiom=idiom
  for filters in [false,true] {
   var settings=ForkExtrasSettings.defaultSettings
   settings.regexMessageFiltersEnabled=filters; settings.hideTabBar=true
   for mask in 0..<8 {
    let media=MediaInputSettings(enableRaiseToSpeak: false,pauseMusicOnRecording: mask & 1 != 0,pauseMusicOnVoiceRecording: mask & 2 != 0,pauseMusicOnVoicePlayback: mask & 4 != 0)
    for category in [ForkExtrasControllerFocus.top,.ninja,.ghost,.privacy,.interface,.chat,.network,.messageSaving,.messageFilters] {
     let entries=forkExtrasControllerEntries(settings: settings,autoFetchPublicMtProxy: false,showCallsTab: true,mediaInputSettings: media,focus: category)
     let ids=entries.map { $0.stableId }
     precondition(Set(ids).count == ids.count,"Duplicate IDs")
     for (a,b) in zip(entries,entries.dropFirst()) { precondition(a < b,"Incorrect stable order: \(category): \(a.stableId)/\(b.stableId)") }
     if category == .top { precondition(ids == [8,0,1,2,3,4,5,6,7]) }
     if category == .chat {
      var values: [Int32:Bool]=[:]
      for entry in entries { if case let .musicPolicy(id,_,value)=entry { values[id]=value } }
      precondition(values == [2001:media.pauseMusicOnRecording,2002:media.pauseMusicOnVoiceRecording,2003:media.pauseMusicOnVoicePlayback])
     }
     if category == .interface { precondition(ids.contains(1521) && ids.contains(140)); precondition(ids.contains(63) == (idiom == .phone)) }
     if category == .network { precondition(ids.contains(138)); precondition(!ids.contains(142) && !ids.contains(140) && ids.contains(146)) }
     if category == .privacy { precondition(ids.contains(44)) }
    }
   }
  }
 }
}
print("Actual Extras factory: 576 preference/device/language combinations, unique ordered IDs, destinations and persisted audio values passed")
"""
    with tempfile.TemporaryDirectory(prefix='banana-menus-') as temp:
        path=pathlib.Path(temp)/'main.swift';path.write_text(stubs+prefs+'\n'+media+'\n'+defs+'\n'+tests,encoding='utf-8')
        subprocess.run(['swift','-swift-version','5',str(path)],check=True,timeout=120)
        for name in [EXTRAS,'submodules/SettingsUI/Sources/Search/SettingsSearchableItems.swift','submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift','submodules/SettingsUI/Sources/Data and Storage/DataAndStorageSettingsController.swift','submodules/SettingsUI/Sources/Themes/ThemeSettingsController.swift']:
            subprocess.run(['swiftc','-frontend','-parse',str(ROOT/name)],check=True,timeout=120)
if __name__ == '__main__':
    result=unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(Placement))
    if not result.wasSuccessful(): sys.exit(1)
    if '--structural-only' not in sys.argv: swift_tests()
