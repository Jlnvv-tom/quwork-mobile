#!/usr/bin/env bash
# Start the configured Android AVD and wait until adb reports it ready.
set -euo pipefail
ROOT=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[[ -f "$ROOT/tooling/env.sh" ]] && source "$ROOT/tooling/env.sh"
ADB_BIN="${ADB:-$(command -v adb || true)}"
EMULATOR_BIN="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}/emulator/emulator"
[[ -x "$EMULATOR_BIN" ]] || EMULATOR_BIN="$(command -v emulator || true)"
[[ -n "$ADB_BIN" && -n "$EMULATOR_BIN" ]] || { echo "找不到 adb 或 emulator" >&2; exit 1; }
DEVICE="${QUWORK_ANDROID_DEVICE:-}"
if [[ -z "$DEVICE" ]]; then DEVICE=$("$ADB_BIN" devices | awk 'NR > 1 && $2 == "device" { print $1 }' | head -n 1); fi
if [[ -n "$DEVICE" ]]; then echo "复用已启动设备：$DEVICE"; exit 0; fi
AVD="${QUWORK_ANDROID_AVD:-$($EMULATOR_BIN -list-avds | head -n 1)}"
[[ -n "$AVD" ]] || { echo "没有 Android AVD，请先在 Android Studio 创建" >&2; exit 1; }
echo "启动 Android AVD：$AVD"
"$EMULATOR_BIN" -avd "$AVD" -no-snapshot-load >/tmp/quwork-android-emulator.log 2>&1 &
for _ in $(seq 1 120); do
  DEVICE=$("$ADB_BIN" devices | awk 'NR > 1 && $2 == "device" { print $1 }' | head -n 1)
  [[ -n "$DEVICE" ]] && echo "模拟器已就绪：$DEVICE" && exit 0
  sleep 1
done
echo "模拟器启动超时，日志：/tmp/quwork-android-emulator.log" >&2
exit 1
