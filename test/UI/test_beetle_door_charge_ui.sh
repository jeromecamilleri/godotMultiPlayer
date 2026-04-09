#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
exec python3 test/UI/test_beetle_door_charge_ui.py "$@"
