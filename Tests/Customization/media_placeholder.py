"""Verify real media-placeholder handlers and restriction priority without UIKit."""
import pathlib
import re
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'submodules/MediaPickerUI/Sources/MediaPickerPlaceholderNode.swift').read_text()
start = source.index('    enum Content {')
end = source.index('\n    }', start) + len('\n    }')
fixture = 'final class Placeholder {\n' + source[start:end] + '''
    var boostPressed: () -> Void = {}
    var settingsPressed: () -> Void = {}
    var cameraPressed: () -> Void = {}
'''
for signature in ['    private func activatePrimaryAction(', '    private func activateCamera(']:
    start = source.index(signature)
    end = source.index('\n    }', start) + len('\n    }')
    fixture += source[start:end].replace('private ', '') + '\n'
fixture += '''
}
let node = Placeholder()
var boosts = 0
var settings = 0
var camera = 0
node.boostPressed = { boosts += 1 }
node.settingsPressed = { settings += 1 }
node.cameraPressed = { camera += 1 }
for content: Placeholder.Content in [.intro(story: false), .bannedSendMedia(text: "Restricted", canBoost: true), .intro(story: true), .bannedSendMedia(text: "Restricted", canBoost: false)] {
    let previousBoosts = boosts
    let previousSettings = settings
    let previousCamera = camera
    node.activatePrimaryAction(content: content)
    node.activateCamera(content: content, hasCamera: false)
    precondition(camera == previousCamera)
    node.activateCamera(content: content, hasCamera: true)
    switch content {
    case .intro:
        precondition(settings == previousSettings + 1 && camera == previousCamera + 1 && boosts == previousBoosts)
    case let .bannedSendMedia(_, canBoost):
        precondition(settings == previousSettings && camera == previousCamera && boosts == previousBoosts + (canBoost ? 1 : 0))
    }
}
enum State { case noAccess(Bool), ready }
'''
screen = (root / 'submodules/MediaPickerUI/Sources/MediaPickerScreen.swift').read_text()
condition = re.search(r'if case let \.noAccess\(cameraAccess\) = self.state[^\n]+', screen)[0].replace('self.state', 'state')
fixture += 'func showsAccessIntro(_ state: State, _ bannedSendMedia: Bool?) -> Bool {\n' + condition + '\n        return cameraAccess\n    }\n    return false\n}\n'
fixture += '''
precondition(showsAccessIntro(.noAccess(true), nil))
precondition(!showsAccessIntro(.noAccess(true), true))
precondition(!showsAccessIntro(.ready, nil))
print("Media placeholder: settings/boost/camera gates, content reuse and restriction priority passed")
'''
with tempfile.TemporaryDirectory(prefix='liquid-media-placeholder-') as directory:
    path = pathlib.Path(directory) / 'main.swift'
    path.write_text(fixture)
    subprocess.run(['swift', str(path)], check=True, cwd=root)
