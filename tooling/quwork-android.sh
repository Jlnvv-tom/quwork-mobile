#!/usr/bin/env bash
# Build, install and launch QuWork on an Android emulator or connected device.
set -euo pipefail

ROOT=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
APP="$ROOT/app"
PKG=io.github.ccch1mneyyy.dsh_app
PORT="${QUWORK_MOCK_PORT:-8787}"
DEVICE="${QUWORK_ANDROID_DEVICE:-}"
BACKEND="${QUWORK_BACKEND:-mock}"
BUILD_MODE="${QUWORK_BUILD_MODE:-debug}"
BUILD_ONLY=0

usage() {
  cat <<'EOF'
用法：tooling/quwork-android.sh [选项]

  --backend mock|dev|prod   后端环境，默认 mock
  --device SERIAL           指定 adb 设备
  --release                 构建 release APK（默认 debug）
  --build-only              只构建，不安装和启动
  --analyze                 只运行 Flutter analyze
EOF
}

while (($#)); do
  case "$1" in
    --backend) BACKEND="${2:?--backend 需要值}"; shift 2 ;;
    --backend=*) BACKEND="${1#*=}"; shift ;;
    --device|-d) DEVICE="${2:?--device 需要设备序列号}"; shift 2 ;;
    --release) BUILD_MODE=release; shift ;;
    --build-only) BUILD_ONLY=1; shift ;;
    --analyze) exec "$ROOT/tooling/quwork-analyze.sh" ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

case "$BACKEND" in mock|dev|prod) ;; *) echo "backend 必须是 mock、dev 或 prod" >&2; exit 2 ;; esac
[[ -f "$ROOT/tooling/env.sh" ]] && source "$ROOT/tooling/env.sh"
CONFIG_FILE="${QUWORK_CONFIG_FILE:-$ROOT/tooling/quwork.env}"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
FLUTTER_BIN="${DSH_FLUTTER_BIN:-${FLUTTER:-${FLUTTER_ROOT:-}/bin/flutter}}"
[[ -x "$FLUTTER_BIN" ]] || FLUTTER_BIN="$(command -v flutter || true)"
[[ -n "$FLUTTER_BIN" && -x "$FLUTTER_BIN" ]] || { echo "找不到 Flutter，请设置 DSH_FLUTTER_BIN" >&2; exit 1; }
ADB_BIN="${ADB:-$(command -v adb || true)}"
[[ -n "$ADB_BIN" ]] || { echo "找不到 adb，请设置 ADB" >&2; exit 1; }
devices() { "$ADB_BIN" devices | awk 'NR > 1 && $2 == "device" { print $1 }'; }
if [[ -z "$DEVICE" ]]; then DEVICE="$(devices | head -n 1)"; fi
if [[ -z "$DEVICE" ]]; then "$ROOT/tooling/quwork-emulator.sh"; DEVICE="$(devices | head -n 1)"; fi
[[ -n "$DEVICE" ]] || { echo "没有可用的 Android 设备" >&2; exit 1; }
"$ADB_BIN" -s "$DEVICE" wait-for-device >/dev/null
for _ in $(seq 1 90); do
  [[ "$($ADB_BIN -s "$DEVICE" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] && break
  sleep 1
done
[[ "$($ADB_BIN -s "$DEVICE" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] || { echo "Android 启动超时" >&2; exit 1; }

case "$BACKEND" in
  mock)
    API_BASE="http://10.0.2.2:$PORT"; LLM_BASE="http://10.0.2.2:$PORT/v1"
    MOCK_DART="${DART:-${FLUTTER_ROOT:-$HOME/dev/flutter}/bin/cache/dart-sdk/bin/dart}"
    MOCK_PID=""
    if ! (command -v curl >/dev/null 2>&1 && curl -fsS --max-time 1 "http://127.0.0.1:$PORT/api/user/self" >/dev/null); then
      [[ -x "$MOCK_DART" ]] || { echo "找不到 Dart，请设置 DART" >&2; exit 1; }
      PORT="$PORT" "$MOCK_DART" "$ROOT/tool/quwork_mock_server.dart" >/tmp/quwork-mock-server.log 2>&1 & MOCK_PID=$!
      trap '[[ -n "${MOCK_PID:-}" ]] && kill "$MOCK_PID" 2>/dev/null || true' EXIT INT TERM
      sleep 1
    fi
    ;;
  dev)
    API_BASE="${QUWORK_DEV_API_BASE_URL:-}"
    [[ -n "$API_BASE" ]] || { echo "开发服必须设置 QUWORK_DEV_API_BASE_URL，例如 https://dev.example.com" >&2; exit 1; }
    LLM_BASE="${QUWORK_DEV_LLM_BASE_URL:-$API_BASE/v1}" ;;
  prod)
    API_BASE="${QUWORK_PROD_API_BASE_URL:-https://llm.rrzu.com}"
    LLM_BASE="${QUWORK_PROD_LLM_BASE_URL:-https://llm.rrzu.com/v1}" ;;
esac

if ((BUILD_ONLY)); then
  rm -f "$APP/build/app/outputs/flutter-apk/app-arm64-debug.apk"
  if [[ "$BUILD_MODE" == release ]]; then
    exec "$ROOT/tooling/build-apk.sh" --release -f arm64 -- "--dart-define=QUWORK_API_BASE_URL=$API_BASE" "--dart-define=QUWORK_LLM_BASE_URL=$LLM_BASE"
  fi
  (cd "$APP" && "$FLUTTER_BIN" build apk --debug --target-platform android-arm64 "--dart-define=QUWORK_API_BASE_URL=$API_BASE" "--dart-define=QUWORK_LLM_BASE_URL=$LLM_BASE") || {
    [[ -s "$APP/build/app/outputs/flutter-apk/app-arm64-debug.apk" ]] || exit 1
    echo "Flutter 未识别带 ABI 后缀的输出路径，已使用已生成的 Debug APK" >&2
  }
  exit 0
fi
if [[ "$BUILD_MODE" == release ]]; then
  "$ROOT/tooling/build-apk.sh" --release -f arm64 -- "--dart-define=QUWORK_API_BASE_URL=$API_BASE" "--dart-define=QUWORK_LLM_BASE_URL=$LLM_BASE"
  APK="$APP/build/app/outputs/flutter-apk/app-arm64-release.apk"
else
  rm -f "$APP/build/app/outputs/flutter-apk/app-arm64-debug.apk"
  (cd "$APP" && "$FLUTTER_BIN" build apk --debug --target-platform android-arm64 "--dart-define=QUWORK_API_BASE_URL=$API_BASE" "--dart-define=QUWORK_LLM_BASE_URL=$LLM_BASE") || {
    [[ -s "$APP/build/app/outputs/flutter-apk/app-arm64-debug.apk" ]] || exit 1
    echo "Flutter 未识别带 ABI 后缀的输出路径，已使用已生成的 Debug APK" >&2
  }
  APK="$APP/build/app/outputs/flutter-apk/app-arm64-debug.apk"
fi
[[ -f "$APK" ]] || { echo "APK 未生成：$APK" >&2; exit 1; }
"$ADB_BIN" -s "$DEVICE" install -r "$APK" >/dev/null
"$ADB_BIN" -s "$DEVICE" shell am force-stop "$PKG"
"$ADB_BIN" -s "$DEVICE" shell am start -n "$PKG/.LauncherMist" >/dev/null
echo "已启动 QuWork：设备=$DEVICE，环境=$BACKEND，API=$API_BASE，LLM=$LLM_BASE"
