#!/bin/bash
# 检查编译产物里有没有类还走「隔离析构」释放路径（CLAUDE.md 禁令 18）。
#
# 用法：scripts/check-isolated-deinit.sh <PinYintone.app 的路径>
#
# 为什么查二进制而不是只靠单元测试：
#   - 崩溃只在部分系统版本的运行时里出现（iOS 18.5 / 26.2 实测崩，26.4 不崩），
#     CI 的模拟器版本一换，测试就可能悄悄测不到；
#   - 单元测试只覆盖被实例化并释放过的类，新加的类没人测就漏了。
#   这里直接看每个类的释放函数有没有调 swift_task_deinitOnExecutor*，
#   与跑在哪个系统上、有没有测试无关。
#
# 修法：给报出来的类加一行 `nonisolated deinit {}`。
set -euo pipefail

APP="${1:?用法：$0 <PinYintone.app 的路径>}"

# Debug 构建的代码在 PinYintone.debug.dylib 里，Release 在主可执行文件里。
BIN="$APP/PinYintone.debug.dylib"
[ -f "$BIN" ] || BIN="$APP/PinYintone"
[ -f "$BIN" ] || { echo "找不到可执行文件：$APP" >&2; exit 2; }

# 没有任何释放函数说明反汇编或符号格式变了——宁可报错，也不能当成「没问题」。
TOTAL=$(xcrun nm "$BIN" | grep -c 'fD$' || true)
if [ "$TOTAL" -eq 0 ]; then
    echo "在 $BIN 里没找到任何类的释放函数（符号以 fD 结尾），检查本身失效了" >&2
    exit 2
fi

# 符号以 fD 结尾 = 某个类的 deallocating deinit。
# ResourceBundleClass 是 Xcode 生成的（GeneratedAssetSymbols.swift），
# 只以 `Bundle(for: ResourceBundleClass.self)` 取类型、从不实例化，也没法改它。
OFFENDERS=$(xcrun otool -tV "$BIN" \
    | awk '/^_.*:$/ { fn = $0 } /deinitOnExecutor/ && fn ~ /fD:$/ { print fn }' \
    | sort -u | sed 's/:$//' | xcrun swift-demangle \
    | grep -v 'ResourceBundleClass' || true)

if [ -n "$OFFENDERS" ]; then
    echo "以下类仍走隔离析构，在 iOS 18.5 / 26.2 上释放即崩溃（CLAUDE.md 禁令 18）：" >&2
    echo "$OFFENDERS" | sed 's/^_*/  /' >&2
    echo "修法：给这些类各加一行 nonisolated deinit {}" >&2
    exit 1
fi

echo "通过：$TOTAL 个释放函数都不走隔离析构路径"
