#!/usr/bin/env bash
# 启动应用并附加 LLDB 调试器
#
# 用法:
#   ./dev/debug-simulator.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

BUNDLE_ID="${BUNDLE_ID:-live.bchat.origin}"
SIM_NAME="${SIM_NAME:-iPhone 17}"

# 先构建
echo "==> 构建应用..."
./dev/run-simulator.sh --no-build 2>/dev/null || ./dev/run-simulator.sh

# 找到模拟器
SIM_UUID="$(xcrun simctl list devices booted 2>/dev/null | grep -oE '[0-9A-F-]{36}' | head -1)"
if [[ -z "$SIM_UUID" ]]; then
    SIM_UUID="$(xcrun simctl list devices available 2>/dev/null | grep -E "$SIM_NAME" | grep -oE '[0-9A-F-]{36}' | head -1)"
fi

# 启动应用（等待调试器）
echo "==> 启动应用（等待调试器附加）..."
PID=$(xcrun simctl launch --wait-for-debugger "$SIM_UUID" "$BUNDLE_ID" 2>&1 | grep -oE '[0-9]+$')

echo "==> 应用已启动，PID: $PID"
echo "==> 附加 LLDB 调试器..."
echo ""

# 启动 LLDB
lldb -p "$PID"
