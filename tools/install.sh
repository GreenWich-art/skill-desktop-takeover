#!/bin/sh
# axctl 安装脚本（desktop-takeover skill 内置 AX 兜底工具）
#
# 策略（与 macos-vision-ocr 的 install.sh 一致）：
#   有 swiftc  → 现场编译（推荐：源码可审计、适配本机架构、无二进制信任问题）
#   无 swiftc  → 使用随包预编译二进制（仅 Apple Silicon / arm64，ad-hoc 签名）
#
# 用法：sh tools/install.sh   （在 skill 目录内任意位置运行均可，自动定位）
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BIN="$SCRIPT_DIR/axctl"
SRC="$SCRIPT_DIR/axctl.swift"

echo "== axctl install =="
echo "skill 目录: $SCRIPT_DIR"

if command -v swiftc >/dev/null 2>&1; then
    echo "检测到 swiftc，现场编译（推荐：源码可审计，适配本机架构）"
    swiftc -O "$SRC" -o "$BIN"
    echo "编译完成: $BIN"
else
    echo "未检测到 swiftc，改用随包预编译二进制"
    if [ "$(uname -m)" != "arm64" ]; then
        echo "错误：当前架构 $(uname -m) 没有随包预编译二进制。" >&2
        echo "请先安装 Xcode Command Line Tools 再重跑本脚本：" >&2
        echo "    xcode-select --install" >&2
        exit 1
    fi
    echo "使用预编译二进制: $BIN（仅 arm64）"
    # 从网络下载的包会被 macOS 打上隔离属性，ad-hoc 签名二进制可能被 GateChecker 拦截
    xattr -d com.apple.quarantine "$BIN" 2>/dev/null || true
fi

chmod +x "$BIN"

echo "== 自检 =="
OUT=$("$BIN" list com.apple.finder 2>&1) && RC=0 || RC=$?
if [ "$RC" -eq 0 ]; then
    echo "PASS: axctl 可运行（list com.apple.finder 输出首行: $(echo "$OUT" | head -1)）"
    echo "提示：AX 读取需要「辅助功能」TCC 权限，未授权时输出可能为空，授权方法见 SKILL.md「AX 兜底层」章节"
else
    echo "FAIL: axctl 运行异常（exit=$RC）" >&2
    echo "$OUT" >&2
    exit 1
fi

echo "== 完成 =="
echo "后续可直接使用: $BIN"
