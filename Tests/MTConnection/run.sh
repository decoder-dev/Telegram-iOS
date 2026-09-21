#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$ROOT"
SOURCES="${MT_CONNECTION_SOURCE_ROOT:-$ROOT/submodules/MtProtoKit/Sources}"
clang -fobjc-arc -framework Foundation -I submodules/MtProtoKit/PublicHeaders \
  -I submodules/MtProtoKit/Sources \
  "$SOURCES/MTTimer.m" "$SOURCES/MTTcpConnectionBehaviour.m" \
  submodules/MtProtoKit/Sources/MTQueue.m Tests/MTConnection/main.m -o "$TMP/tests"
if [ "$#" -eq 0 ]; then
  set -- rearm manual-rearm restart-deadline disabled cancel-retry retry-floor
fi
for test in "$@"; do
  "$TMP/tests" "$test"
done
