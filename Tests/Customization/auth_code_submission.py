"""Check the production paste/autofill path submits a completed login code once."""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
source = (ROOT / 'submodules/AuthorizationUI/Sources/AuthorizationSequenceCodeEntryControllerNode.swift').read_text()


def section(start, end):
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


methods = section('    func updateCode(_ code: String)', '    func resetCode()')
methods += section('    private func codeChanged(text: String)', '    func textField(_ textField: UITextField, shouldChangeCharactersIn')
fixture = r'''
import Foundation
enum SentAuthorizationCodeType {
    case call(Int32), otherSession(Int32), missedCall(String, Int32), sms(Int32)
    case fragment(String, Int32), email(String, Int32, Int32?, Int32?, String, Bool), firebase(String, Int32)
    case word(String?), phrase(String?), flashCall, emailSetupRequired
}
final class CodeInput { var text = "" }
final class Harness {
    let codeInputView = CodeInput()
    var inProgress = false
    var codeType: SentAuthorizationCodeType?
    var loginWithCode: ((String) -> Void)?
    var updateNextEnabled: ((Bool) -> Void)?
'''
checks = r'''
}
let types: [SentAuthorizationCodeType] = [
    .sms(5), .call(5), .otherSession(5), .missedCall("+123", 5),
    .fragment("https://fragment.com", 5), .email("***", 5, nil, nil, "", false), .firebase("", 5)
]
for type in types {
    let harness = Harness()
    harness.codeType = type
    var submitted: [String] = []
    harness.loginWithCode = { submitted.append($0) }
    harness.updateCode("1234")
    precondition(submitted.isEmpty)
    harness.updateCode("12345")
    precondition(submitted == ["12345"], "A single completed code must submit exactly once")
    harness.inProgress = true
    harness.updateCode("54321")
    precondition(harness.codeInputView.text == "12345", "An active request must not be replaced by paste")
    precondition(submitted == ["12345"])
}
print("Authorization submission: seven delivery methods, incomplete/full/busy code passed")
'''

with tempfile.TemporaryDirectory(prefix='liquid-auth-submit-') as directory:
    path = pathlib.Path(directory) / 'main.swift'
    path.write_text(fixture + methods + checks)
    subprocess.run(['swift', str(path)], check=True, cwd=ROOT)
