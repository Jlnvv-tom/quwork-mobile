#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[[ -f "$ROOT/tooling/env.sh" ]] && source "$ROOT/tooling/env.sh"
DART_BIN="${DART:-$(command -v dart || true)}"
[[ -n "$DART_BIN" ]] || DART_BIN="${FLUTTER_ROOT:-$HOME/dev/flutter}/bin/cache/dart-sdk/bin/dart"
[[ -x "$DART_BIN" ]] || { echo "找不到 Dart，请设置 DART" >&2; exit 1; }
exec env PORT="${QUWORK_MOCK_PORT:-8787}" "$DART_BIN" "$ROOT/tool/quwork_mock_server.dart"
