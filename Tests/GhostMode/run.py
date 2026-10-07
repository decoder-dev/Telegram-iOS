import pathlib
import subprocess
import tempfile
root = pathlib.Path(__file__).resolve().parents[2]
settings = (root / "submodules/TelegramCore/Sources/Settings/TelegramSimpleSettings.swift").read_text(encoding="utf-8").replace("import Postbox\n", "").replace("import SwiftSignalKit\n", "")
source = (root / "submodules/TelegramCore/Sources/Arena/BananaGhostLocalRead.swift").read_text(encoding="utf-8").replace("import Postbox\n", "")
fixture = (pathlib.Path(__file__).with_name("Fixture.swift")).read_text(encoding="utf-8")
with tempfile.TemporaryDirectory() as tmp:
    path = pathlib.Path(tmp) / "main.swift"
    path.write_text(settings + fixture + source + (pathlib.Path(__file__).with_name("Checks.swift")).read_text(), encoding="utf-8")
    subprocess.run(["swift", "-swift-version", "5", str(path)], check=True, timeout=120)
