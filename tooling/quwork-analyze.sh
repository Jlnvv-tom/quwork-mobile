#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[[ -f "$ROOT/tooling/env.sh" ]] && source "$ROOT/tooling/env.sh"
cd "$ROOT/app"
flutter analyze
