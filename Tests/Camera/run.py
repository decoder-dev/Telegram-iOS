"""Run production picker completion/cancellation gates without UIKit."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
for component, value_type in [('ChatScheduleTimeController', 'Result'), ('ChatTimerScreen', 'Int32?')]:
    filename = 'ChatScheduleTimeScreen.swift' if component == 'ChatScheduleTimeController' else 'ChatTimerScreen.swift'
    source = (root / 'submodules/TelegramUI/Components' / component / 'Sources' / filename).read_text(encoding='utf-8')
    start = source.index('    fileprivate let completion:')
    end = source.index('        super.dismiss(completion: completion)', start)
    end = source.index('    }', end) + 5
    gate = source[start:end]
    assert 'controller.completion(' not in source, 'All picker selections must use the once-only gate'
    fixture = """
import Foundation
class Base {
    var dismissals = 0
    func dismiss(completion: (() -> Void)? = nil) { dismissals += 1; completion?() }
}
final class Picker: Base {
    typealias Result = Int32
""" + gate + """
    init(_ completion: @escaping (""" + value_type + """) -> Void) { self.completion = completion }
}
var sent = 0
var cancelled = 0
let confirmed = Picker { _ in sent += 1 }
confirmed.cancelled = { cancelled += 1 }
confirmed.complete(10)
confirmed.complete(20)
confirmed.dismiss()
precondition(sent == 1 && cancelled == 0)
let abandoned = Picker { _ in sent += 1 }
abandoned.cancelled = { cancelled += 1 }
abandoned.dismiss()
abandoned.dismiss()
abandoned.complete(30)
precondition(sent == 1 && cancelled == 1)
print("Picker confirmation/cancellation gates passed")
"""
    with tempfile.TemporaryDirectory() as directory:
        path = pathlib.Path(directory) / 'main.swift'
        path.write_text(fixture, encoding='utf-8')
        subprocess.run(['swift', str(path)], check=True)
