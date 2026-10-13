#!/bin/bash
# 找到指定系统版本、指定机型的模拟器，启动并等它就绪，把 UDID 打到标准输出。
#
# 用法：scripts/ci-pick-simulator.sh <iOS 版本 | latest> <机型名>
#   例：scripts/ci-pick-simulator.sh 18.5 "iPhone 16 Pro"
#
# 为什么不直接把版本和机型写进 xcodebuild 的 -destination：
#   GitHub 的 macOS 机器上，刚 xcode-select 切完 Xcode 时模拟器服务还没起来，
#   xcodebuild 等 60 秒找不到任何模拟器就报
#   「Unable to find a device matching the provided destination specifier」。
#   同一个镜像时好时坏。这里先唤醒服务、带重试地找到设备并启动，再交给 xcodebuild。
#
# 找不到时列出镜像里实际有的 iPhone 模拟器并失败——不换成别的版本顶替：
# 旧系统那几路存在的意义就是在**那个**版本上跑（CLAUDE.md 禁令 18）。
set -euo pipefail

WANT_OS="${1:?用法：$0 <iOS 版本 | latest> <机型名>}"
WANT_NAME="${2:?用法：$0 <iOS 版本 | latest> <机型名>}"

pick() {
    xcrun simctl list devices available -j 2>/dev/null | python3 -c '
import json, sys
want_os, want_name = sys.argv[1], sys.argv[2]
try:
    devices = json.load(sys.stdin)["devices"]
except Exception:
    sys.exit(3)                      # 服务还没就绪，输出不是合法 JSON
found = []                           # [(版本元组, udid)]
listing = []
for runtime, devs in devices.items():
    if ".SimRuntime.iOS-" not in runtime:
        continue
    version = runtime.rsplit("iOS-", 1)[1].replace("-", ".")
    for d in devs:
        if not d.get("isAvailable", True) or not d["name"].startswith("iPhone"):
            continue
        listing.append("iOS %s  %s" % (version, d["name"]))
        if d["name"] == want_name and want_os in ("latest", version):
            found.append((tuple(int(x) for x in version.split(".")), d["udid"]))
if not found:
    sys.stderr.write("\n".join(sorted(set(listing))) + "\n")
    sys.exit(4 if listing else 3)    # 4 = 有模拟器但没有要的那个；3 = 一个都没有
print(max(found)[1])
' "$WANT_OS" "$WANT_NAME"
}

# 最多等 3 分钟。「一个模拟器都没有」(3) 值得重试；「有但没有要的」(4) 再等也不会有。
UDID=""
ERR=$(mktemp)
for attempt in $(seq 1 18); do
    set +e
    UDID=$(pick 2>"$ERR"); rc=$?
    set -e
    [ $rc -eq 0 ] && break
    if [ $rc -eq 4 ]; then
        echo "镜像里没有「iOS $WANT_OS / $WANT_NAME」这个模拟器。实际有的 iPhone 模拟器：" >&2
        sed 's/^/  /' "$ERR" >&2
        echo "请改 .github/workflows/ci.yml 里 matrix 的版本或机型。" >&2
        exit 1
    fi
    echo "模拟器服务还没就绪（第 $attempt 次），10 秒后重试…" >&2
    sleep 10
done
if [ -z "$UDID" ]; then
    echo "等了 3 分钟，模拟器服务始终没有列出任何 iPhone 模拟器。" >&2
    exit 1
fi

# 启动并阻塞到系统就绪；已经在运行时 bootstatus 直接返回。
xcrun simctl bootstatus "$UDID" -b >&2
echo "$UDID"
