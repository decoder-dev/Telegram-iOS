#!/usr/bin/env bash
# 生成 Xcode 项目并打开，用于在 Xcode 中调试
#
# 用法:
#   ./dev/open-xcode.sh
#
# 前置: 已生成过配置（build-system/bchat-configuration.json）且子模块已初始化。
# 首次运行后需要执行 ./dev/setup-fake-profile.sh 生成假 profile，才能在 Xcode 中点击 Run。

set -euo pipefail

# ===== 定位仓库根目录 =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# ===== 配置 =====
CONFIG_PATH="${CONFIG_PATH:-build-system/bchat-configuration.json}"
CACHE_DIR="${CACHE_DIR:-$HOME/telegram-bazel-cache}"

if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "错误: 配置文件不存在: $CONFIG_PATH" >&2
    echo "请先创建配置文件（参考 build-system/template_minimal_development_configuration.json）" >&2
    exit 1
fi

# ===== 生成 Xcode 项目 =====
echo "==> 生成 Xcode 项目..."
echo "    配置: $CONFIG_PATH"
echo "    缓存: $CACHE_DIR"
echo ""

python3 build-system/Make/Make.py \
    --overrideXcodeVersion \
    --cacheDir "$CACHE_DIR" \
    generateProject \
    --configurationPath "$CONFIG_PATH" \
    --xcodeManagedCodesigning

# 设置独立的 DerivedData 路径避免权限问题
DERIVED_DATA_PATH="$HOME/telegram-xcode-build"
mkdir -p "$DERIVED_DATA_PATH"

echo ""
echo "==> 设置独立的 DerivedData 路径: $DERIVED_DATA_PATH"
defaults write com.apple.dt.Xcode IDECustomDerivedDataLocation "$DERIVED_DATA_PATH"

echo ""
echo "==> 完成！Xcode 项目已打开。"
echo ""
echo "📝 首次使用 Xcode 调试的提示："
echo "   1. 如果 Xcode 报 provisioning profile 错误，运行："
echo "      ./dev/setup-fake-profile.sh"
echo ""
echo "   2. 在 Xcode 中选择模拟器设备，然后点击 ⌘R 即可运行并调试"
echo ""
echo "   3. 命令行构建使用 ./dev/run-simulator.sh（更快，但不能断点调试）"
