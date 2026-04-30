#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR="${1:-/tmp/swim-pose-ui}"
GODOT_BIN="${GODOT_BIN:-/dataSSD/Godot_v4.6.2-stable_linux.x86_64}"
DISPLAY_ID="${SWIM_POSE_UI_DISPLAY:-:98}"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

cleanup() {
	pkill -f "Xvfb ${DISPLAY_ID}" >/dev/null 2>&1 || true
	pkill -f "openbox" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

Xvfb "$DISPLAY_ID" -screen 0 1280x720x24 >"$OUT_DIR/xvfb.log" 2>&1 &
sleep 0.5
DISPLAY="$DISPLAY_ID" openbox >"$OUT_DIR/openbox.log" 2>&1 &
sleep 0.5

DISPLAY="$DISPLAY_ID" "$GODOT_BIN" \
	--rendering-driver opengl3 \
	--path "$ROOT_DIR" \
	-s "res://test/UI/swim_pose_visual_probe.gd" \
	-- "$OUT_DIR" \
	>"$OUT_DIR/godot.log" 2>&1

python3 - "$OUT_DIR" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
summary_path = out_dir / "summary.json"
if not summary_path.exists():
	raise SystemExit(f"summary.json manquant dans {out_dir}")

summary = json.loads(summary_path.read_text(encoding="utf-8"))
angle = float(summary["face_angle_from_expected_degrees"])
face_y = float(summary["face_direction_y"])
pitch = float(summary["model_pitch_degrees"])
screenshot = Path(summary["screenshot"])

if not screenshot.exists() or screenshot.stat().st_size <= 0:
	raise SystemExit(f"capture swim_pose.png absente ou vide: {screenshot}")
if angle > 5.0:
	raise SystemExit(f"regard mal oriente: angle={angle:.2f}, attendu <= 5 degres vers l'avant")
if face_y < 0.25:
	raise SystemExit(f"regard pas assez releve: face_y={face_y:.2f}, attendu >= 0.25")
if not (75.0 <= pitch <= 85.0):
	raise SystemExit(f"buste pas assez horizontal: pitch={pitch:.2f}, attendu ~80 degres")

print(f"swim pose UI OK: face_angle={angle:.2f}, face_y={face_y:.2f}, pitch={pitch:.2f}, capture={screenshot}")
PY
