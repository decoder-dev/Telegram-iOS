"""Compile both production Web proxy codecs together and check their wire data."""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCES = ROOT / 'submodules/WebProxyTransport/Sources'
fixture = '''import Foundation
let payload = Data([3, 7, 11])
let legacy = LegacyWebProxyFrame(type: .data, streamId: 42, payload: payload)
let modern = WebProxyFrame(type: .data, streamId: 42, payload: payload)
let bytes = try WebProxyFrameEncoder.encode(modern)
precondition(bytes == WebProxyFrameCodec.encode(legacy))
let oldDecoded = try WebProxyFrameCodec.decodeBatch(bytes)
precondition(oldDecoded == [legacy])
let decoder = WebProxyFrameDecoder()
precondition(try decoder.append(bytes.prefix(5)).isEmpty)
let decoded = try decoder.append(Data(bytes.dropFirst(5)))
precondition(decoded == [modern])
let legacyHello = LegacyWebProxyFrame.hello()
let hello = WebProxyFrame(type: .hello, streamId: 0, payload: Data([1]))
precondition(WebProxyFrameCodec.encode(legacyHello) == (try WebProxyFrameEncoder.encode(hello)))
let window = WebProxyFrame.window(streamId: 42, delta: 8192)
let legacyWindow = LegacyWebProxyFrame(type: .window, streamId: 42, payload: window.payload)
precondition(WebProxyFrameCodec.encode(legacyWindow) == (try WebProxyFrameEncoder.encode(window)))
do {
    _ = try WebProxyFrameEncoder.encode(WebProxyFrame(type: .data, streamId: 0, payload: payload))
    fatalError("Invalid modern stream admitted")
} catch WebProxyFrameError.invalidFrame {}
do {
    _ = try WebProxyFrameCodec.decodeBatch(Data([0xff, 0, 0, 0, 0, 0, 0, 0]))
    fatalError("Invalid legacy frame admitted")
} catch WebProxyFrameCodecError.invalidFrameType {}
print("Both production codecs compile together; wire bytes, incremental reads and bounds passed")
'''
# Throwing calls must be evaluated outside precondition's nonthrowing autoclosure.
fixture = fixture.replace('precondition(try decoder.append(bytes.prefix(5)).isEmpty)',
                          'let partial = try decoder.append(bytes.prefix(5))\nprecondition(partial.isEmpty)')
fixture = fixture.replace('precondition(WebProxyFrameCodec.encode(legacyHello) == (try WebProxyFrameEncoder.encode(hello)))',
                          'let helloBytes = try WebProxyFrameEncoder.encode(hello)\nprecondition(WebProxyFrameCodec.encode(legacyHello) == helloBytes)')
fixture = fixture.replace('precondition(WebProxyFrameCodec.encode(legacyWindow) == (try WebProxyFrameEncoder.encode(window)))',
                          'let windowBytes = try WebProxyFrameEncoder.encode(window)\nprecondition(WebProxyFrameCodec.encode(legacyWindow) == windowBytes)')
with tempfile.TemporaryDirectory() as directory:
    directory = pathlib.Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture, encoding='utf-8')
    binary = directory / 'web-codecs'
    subprocess.run(['swiftc', str(SOURCES / 'WebProxyFrame.swift'),
                    str(SOURCES / 'WebProxyFrameCodec.swift'),
                    str(SOURCES / 'WebProxyLog.swift'), str(main), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
