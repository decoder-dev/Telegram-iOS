"""Exercise the camera's actual CoreMedia buffer conversion with the shared C DSP."""

import pathlib
import subprocess
import tempfile


root = pathlib.Path(__file__).resolve().parents[2]
dsp = root / 'submodules/ForkVoiceDSP'
headers = dsp / 'PublicHeaders/ForkVoiceDSP'
effect = root / 'submodules/Camera/Sources/RoundVideoVoiceEffect.swift'
fixture = root / 'Tests/Camera/RoundVideoVoiceFixtures.swift'

with tempfile.TemporaryDirectory(prefix='round-video-voice-') as temp:
    directory = pathlib.Path(temp)
    module_map = directory / 'module.modulemap'
    module_map.write_text(f'module ForkVoiceDSP {{ header "{headers / "ForkVoiceDSP.h"}" export * }}\n', encoding='utf-8')
    library = directory / 'voice.o'
    executable = directory / 'round-video-voice'
    subprocess.run(['clang', '-std=c11', '-O2', '-I', str(headers), '-c', str(dsp / 'Sources/ForkVoiceDSP.c'), '-o', str(library)], check=True)
    subprocess.run(['swiftc', '-warnings-as-errors', '-I', str(directory), str(effect), str(fixture), str(library), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
