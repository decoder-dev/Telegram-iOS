#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$ROOT"
SOURCES="${MT_CONNECTION_SOURCE_ROOT:-$ROOT/submodules/MtProtoKit/Sources}"
if [ "$#" -eq 0 ] || [ "$1" = requests ]; then
  python3 Tests/MTConnection/extract_requests.py "$SOURCES/MTRequestMessageService.m" "$TMP/requests.m"
  clang -fobjc-arc -framework Foundation -I submodules/MtProtoKit/PublicHeaders \
    submodules/MtProtoKit/Sources/MTTimer.m submodules/MtProtoKit/Sources/MTQueue.m \
    "$TMP/requests.m" -o "$TMP/requests"
  "$TMP/requests"
  if [ "$#" -ne 0 ]; then exit 0; fi
fi
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
