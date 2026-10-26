# Code scanning remediation — October 2026

## Source changes

Integer products are evaluated in the destination width before allocation-size, stride, offset and accumulator conversions. Floating-point products accumulated in double are evaluated in double except the intentionally float-rounded FFmpeg dither paths. Macro allocation helpers promote their operands before multiplying.

The keyboard-defaults parser uses disjoint escaped/unescaped character alternatives, avoiding exponential backtracking on malformed backslash-heavy strings. A bounded subprocess regression verifies rejection of a 100,000-backslash unterminated string.

## Verification

Local checks completed: FFmpeg and JPEG XL core library builds; libwebp build and three lossless encode/decode pixel comparisons; Clang compilation checks for all changed Watch Opus/WebP codec source units and the OpenSubdiv/CompanionRenderer units.

Apple Silicon Subcodec and Watch Swift-package regression suites run in `.github/workflows/security-regressions.yml`. Full iOS integration is verified by the existing application build before release. The WebAssembly example is not an iOS build target and cannot be executed by the native host checks.

## Reviewed findings

These findings are documented individually in the GitHub Code scanning dashboard; scanning rules remain enabled.

### Alerts 1269, 1270, 1271, 1272, 1273, 1274, 1275, 1276, 1277, 1278, 1279, 1280, 1281, 1282, 1283, 1284, 1285, 1286, 1287, 1288

Reviewed the H.264 bit-depth templates: block is declared int16_t* for the shared interface, while high-bit-depth instantiations store dctcoef as 32-bit coefficients. Multiplying the coefficient offset by sizeof(pixel) (1 for 8-bit, 2 for high-bit-depth) intentionally converts to int16_t storage units. The loop indices are bounded. Removing this scaling would address the wrong coefficient block and corrupt decoding; this is not double-scaling a pointer of the actual stored coefficient type.

### Alerts 224

Reviewed every ParseOffset caller in time_zone_posix.cc: hours are constrained to 0..24 or -167..167, minutes/seconds to 0..59, and sign is +/-1. All intermediate products and the final offset fit signed 32-bit int (absolute value <=604799). The later int_fast32_t conversion cannot expose an overflowing multiplication on any supported ABI.

### Alerts 1236, 1237

Reviewed the floating-point dither template: the products are float operations intentionally accumulated in double, using normalized audio samples, fixed scale and bounded filter/noise-shaping state. They are not integer buffer-size calculations. Promoting these operands changes the specified float rounding of the audio dither path; no pointer, allocation length or security boundary is derived from the product.

### Alerts 4

Reviewed DecryptMatch.py: this is a read-only decoder for existing Fastlane Match encrypted certificate archives. EVP_BytesToKey reproduces the legacy OpenSSL V1 MD5/SHA256 derivation required by that file format; it is not a password verifier or a password-hash database and does not create new encrypted archives. Changing the digest would make existing archives undecryptable. The versioned newer archive decoder uses its own prescribed KDF.
