#!/usr/bin/env bash
# Follow Flutter/QuWork logs from the selected adb device.
set -euo pipefail
[[ -f "$(dirname "$0")/env.sh" ]] && source "$(dirname "$0")/env.sh"
ADB_BIN="${ADB:-$(command -v adb || true)}"; DEVICE="${QUWORK_ANDROID_DEVICE:-}"
[[ -n "$ADB_BIN" ]] || { echo "找不到 adb" >&2; exit 1; }
if [[ -z "$DEVICE" ]]; then DEVICE=$("$ADB_BIN" devices | awk 'NR > 1 && $2 == "device" { print $1 }' | head -n 1); fi
[[ -n "$DEVICE" ]] || { echo "没有在线设备" >&2; exit 1; }
exec "$ADB_BIN" -s "$DEVICE" logcat -v color '*:S' flutter:I io.github.ccch1mneyyy.dsh_app:I
