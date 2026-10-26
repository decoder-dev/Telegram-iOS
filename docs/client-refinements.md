# Client refinements

## Included

- Audio/video speed sliders expose the existing playback engine’s 4× rate.
- An optional Privacy setting removes known tracking parameters from links in newly sent ordinary text messages, including hidden links. It starts disabled and existing saved settings remain compatible.
- Cleanup retains original URL encoding, fragments, time parameters, unknown query parameters and attributed text. Code blocks, inline code, signed/authenticated URLs and rich-document messages are preserved. Editing existing messages is unaffected.

## Verification

`python3 Tests/ForkRefinements/run.py` compiles the actual Foundation helpers and real text attribute types on macOS. Fixtures cover signed URLs, lookalike hosts, Unicode, URL encoding, hidden links, multiple links and retained formatting. The Client regression tests workflow also runs the existing migration, customization, ghost-mode and network tests.

A Linux source review does not establish the appearance of iOS screens. Simulator recording and frame review remain required before claiming visual verification.

## Sources of ideas

The speed-range and link-cleanup ideas were compared with [Zalupagram’s speed change](https://github.com/palenkof/zalupagram-ios/commit/47a5ef5d36) and [tracking-link cleanup](https://github.com/palenkof/zalupagram-ios/commit/72de182c18). The URL cleaner here is a separate implementation with conservative signed-link handling and attributed-text preservation.

Other inspected forks include [Donutgram](https://github.com/kittenello/Donutgram) and [PolySRV](https://github.com/roon9e/polysrv-ios/tree/polysrv). Existing functionality is checked before adding overlapping settings. Custom-backend cryptographic changes and embedded repository credentials are not part of these refinements.
