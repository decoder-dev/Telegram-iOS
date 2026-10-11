"""Compatibility checks for the Telegram 13 integration workspace."""
import pathlib, re, subprocess, unittest, shutil, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[2]
class StorageMigration(unittest.TestCase):
 def test_flatbuffer_declarations_are_unique(self):
  for path in (ROOT/'submodules/TelegramCore/FlatSerialization/Models').glob('*.fbs'):
   source=path.read_text(encoding='utf-8')
   source=re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
   names=re.findall(r'\b(?:table|struct|enum|union)\s+(\w+)',source)
   self.assertEqual(len(names),len(set(names)),path.name)
 def test_persisted_flatbuffer_union_prefixes(self):
  for path, union in [('submodules/TelegramCore/FlatSerialization/Models/RichText.fbs','RichText_Value'),('submodules/TelegramCore/FlatSerialization/Models/InstantPageBlock.fbs','InstantPageBlock_Value')]:
   old=subprocess.check_output(['git','show','6fd195d294be0a6f5a831b2de5671250faaecbe8:'+path],cwd=ROOT).decode()
   new=(ROOT/path).read_text(encoding='utf-8')
   def tags(s):return [x.strip() for x in re.search(r'union '+union+r'\s*\{(.*?)\}',s,re.S)[1].split(',')]
   a,b=tags(old),tags(new)
   self.assertEqual(a,b[:len(a)],path)
   self.assertEqual(len(b),len(set(b)),path)
 def test_api_is_official_snapshot(self):
  for f in (ROOT/'submodules/TelegramApi/Sources').glob('Api[0-9]*.swift'):
   self.assertEqual(f.read_bytes(),subprocess.check_output(['git','show','f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838:'+f.relative_to(ROOT).as_posix()],cwd=ROOT),f.name)
 def test_proxy_codable_roundtrip(self):
  compiler=shutil.which('swiftc')
  if not compiler:self.skipTest('Swift compiler unavailable; codec execution still requires CI')
  s=(ROOT/'submodules/TelegramCore/Sources/SyncCore/SyncCore_ProxySettings.swift').read_text(encoding='utf-8')
  enum=s[s.index('public enum ProxyServerConnection:'):s.index('\npublic struct ProxyServerSettings:')]
  key='''struct StringCodingKey: CodingKey, ExpressibleByStringLiteral {
 var stringValue: String; var intValue: Int? { nil }
 init(stringValue: String) { self.stringValue = stringValue }
 init?(intValue: Int) { return nil }
 init(stringLiteral value: String) { self.stringValue = value }
}
'''
  fixtures='''
func decode(_ json: String) throws -> ProxyServerConnection { try JSONDecoder().decode(ProxyServerConnection.self, from: Data(json.utf8)) }
func expect(_ json: String, _ expected: ProxyServerConnection) throws {
 let actual = try decode(json)
 precondition(actual == expected)
}
let secret = Data([1, 2, 3])
try expect(#"{"_t":3,"secret":"AQID"}"#, .vless(secret: secret))
try expect(#"{"_t":2,"secret":"AQID"}"#, .web(secret: secret))
try expect(#"{"_t":3,"secret":"AQID","path":"relay"}"#, .web(secret: secret, path: "relay"))
try expect(#"{"_t":4,"secret":"AQID","path":"relay"}"#, .web(secret: secret, path: "relay"))
for value in [ProxyServerConnection.vless(secret: secret), .web(secret: secret), .web(secret: secret, path: "relay"), .mtp(secret: secret), .socks5(username: "u", password: "p")] {
 let data = try JSONEncoder().encode(value)
 let decoded = try JSONDecoder().decode(ProxyServerConnection.self, from: data)
 precondition(decoded == value)
 let tag = (try JSONSerialization.jsonObject(with: data) as! [String: Any])["_t"] as! Int
 switch value { case .vless: precondition(tag == 3); case let .web(_, path): precondition(tag == (path.isEmpty ? 2 : 4)); default: break }
}
print("PASS legacy VLESS and official Web proxy codec migrations")
'''
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);(p/'main.swift').write_text('import Foundation\n'+key+enum+fixtures,encoding='utf-8')
   subprocess.run([compiler,str(p/'main.swift'),'-o',str(p/'fixture')],check=True)
   subprocess.run([str(p/'fixture')],check=True)
if __name__=='__main__':unittest.main()
