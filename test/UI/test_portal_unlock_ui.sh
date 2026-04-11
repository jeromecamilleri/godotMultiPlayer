#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"
OUT_DIR="${1:-/tmp/portal-unlock-ui}"
exec python3 test/UI/test_portal_progression_ui.py --phase breche "$OUT_DIR"
