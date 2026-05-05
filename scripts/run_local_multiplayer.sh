#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/dataSSD/godot/bin/godot.linuxbsd.editor.x86_64}"
CLIENTS="${CLIENTS:-2}"
PORT="${PORT:-5050}"
HOST="${HOST:-127.0.0.1}"
SERVER_NAME="${SERVER_NAME:-Player Server}"
PLAYER_PREFIX="${PLAYER_PREFIX:-Player}"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs/local_multiplayer}"
RENDERING_DRIVER="${GODOT_RENDERING_DRIVER:-vulkan}"
PIDS=()

usage() {
	cat <<'USAGE'
Usage:
  scripts/run_local_multiplayer.sh [options]

Starts one Godot server instance and one or more local client instances.

Options:
  --clients N       Number of client windows to launch. Default: 2.
  --port PORT       ENet port. Default: 5050.
  --host HOST       Client host. Default: 127.0.0.1.
  --server-name N   Server window/player name. Default: Player Server.
  --player-prefix P Client names become "P 1", "P 2", ...
  -h, --help        Show this help.

Environment:
  GODOT_BIN=/path/to/godot
  GODOT_RENDERING_DRIVER=vulkan|opengl3
  LOG_DIR=/path/to/logs

The script uses the same UI auto-role hooks as the UI tests:
  UI_TEST_AUTO_ROLE=server|client
  GODOT_RUNTIME_HOST=<host>
  GODOT_RUNTIME_PORT=<port>
  GODOT_PLAYER_NAME=<name>

Stop all launched instances with Ctrl+C.
USAGE
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--clients)
			CLIENTS="${2:-}"
			shift 2
			;;
		--port)
			PORT="${2:-}"
			shift 2
			;;
		--host)
			HOST="${2:-}"
			shift 2
			;;
		--server-name)
			SERVER_NAME="${2:-}"
			shift 2
			;;
		--player-prefix)
			PLAYER_PREFIX="${2:-}"
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			usage >&2
			exit 2
			;;
	esac
done

if [[ ! -x "$GODOT_BIN" ]]; then
	echo "GODOT_BIN is not executable: $GODOT_BIN" >&2
	exit 1
fi
if ! [[ "$CLIENTS" =~ ^[0-9]+$ ]] || [[ "$CLIENTS" -lt 1 ]]; then
	echo "--clients must be a positive integer" >&2
	exit 1
fi
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [[ "$PORT" -lt 1 || "$PORT" -gt 65535 ]]; then
	echo "--port must be between 1 and 65535" >&2
	exit 1
fi

mkdir -p "$LOG_DIR"

cleanup() {
	for pid in "${PIDS[@]}"; do
		if kill -0 "$pid" 2>/dev/null; then
			kill "$pid" 2>/dev/null || true
		fi
	done
}
trap cleanup INT TERM EXIT

launch_instance() {
	local role="$1"
	local name="$2"
	local log_file="$3"
	(
		cd "$ROOT_DIR"
		UI_TEST_AUTO_ROLE="$role" \
		UI_TEST_PORT="$PORT" \
		GODOT_RUNTIME_HOST="$HOST" \
		GODOT_RUNTIME_PORT="$PORT" \
		GODOT_PLAYER_NAME="$name" \
		"$GODOT_BIN" --rendering-driver "$RENDERING_DRIVER" --path "$ROOT_DIR"
	) >"$log_file" 2>&1 &
	PIDS+=("$!")
	echo "Started $role '$name' pid=${PIDS[-1]} log=$log_file"
}

echo "Launching local multiplayer: 1 server + $CLIENTS client(s) on $HOST:$PORT"
launch_instance "server" "$SERVER_NAME" "$LOG_DIR/server.log"
sleep 1.0

for index in $(seq 1 "$CLIENTS"); do
	launch_instance "client" "$PLAYER_PREFIX $index" "$LOG_DIR/client_$index.log"
	sleep 0.35
done

echo "All instances started. Press Ctrl+C to stop."
wait
