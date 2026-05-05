#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/dataSSD/godot/bin/godot.linuxbsd.editor.x86_64}"
BUTLER_BIN="${BUTLER_BIN:-butler}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT_DIR/build/itch}"
TARGET="${TARGET:-linux}"
PRESET="${PRESET:-MultiRobot}"
CHANNEL="${ITCH_CHANNEL:-linux}"
VERSION="${VERSION:-}"
ITCH_TARGET="${ITCH_TARGET:-}"
RUN_TESTS=1
PUBLISH=0
DRY_RUN=0
HIDDEN=0
IF_CHANGED=1

usage() {
	cat <<'USAGE'
Usage:
  ~/bin/butler login
  scripts/release_itch.sh [options]
  exemple :   
  BUTLER_BIN=~/bin/butler \
  ITCH_TARGET=jcamille/godot-multi-player-3d-game \
  scripts/release_itch.sh --publish --version 0.1.0


Build Godot export(s) into build/itch and optionally publish to itch.io with butler.

Options:
  --target linux|windows        Export target. Default: linux.
  --preset NAME                 Godot export preset. Default: MultiRobot.
  --channel NAME                itch.io channel. Default: linux.
  --version VERSION             User-visible release version. Default: git describe/commit.
  --export-only                 Build only. Default.
  --publish                     Build then publish with butler.
  --skip-tests                  Do not run GUT before exporting.
  --hidden                      Pass --hidden to butler when creating a new channel.
  --no-if-changed               Do not pass --if-changed to butler.
  --dry-run                     Print commands without executing export/publish.
  -h, --help                    Show this help.

Environment:
  GODOT_BIN=/path/to/godot
  BUTLER_BIN=/path/to/butler
  ITCH_TARGET=user/game         Required with --publish, for example camille/game
  ITCH_CHANNEL=linux            itch.io channel name
  VERSION=0.1.0                 Optional user-visible build version
  BUILD_ROOT=/path/to/builds    Optional output directory

Examples:
  scripts/release_itch.sh --export-only
  ITCH_TARGET=myuser/mygame scripts/release_itch.sh --publish --version 0.1.0
  ITCH_TARGET=myuser/mygame scripts/release_itch.sh --target windows --preset "Windows Desktop" --channel windows --publish
USAGE
}

log() {
	printf '[release] %s\n' "$*"
}

run_cmd() {
	log "$*"
	if [[ "$DRY_RUN" == "1" ]]; then
		return 0
	fi
	"$@"
}

die() {
	printf '[release] ERROR: %s\n' "$*" >&2
	exit 1
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--target)
			TARGET="${2:-}"
			shift 2
			;;
		--preset)
			PRESET="${2:-}"
			shift 2
			;;
		--channel)
			CHANNEL="${2:-}"
			shift 2
			;;
		--version)
			VERSION="${2:-}"
			shift 2
			;;
		--export-only)
			PUBLISH=0
			shift
			;;
		--publish)
			PUBLISH=1
			shift
			;;
		--skip-tests)
			RUN_TESTS=0
			shift
			;;
		--hidden)
			HIDDEN=1
			shift
			;;
		--no-if-changed)
			IF_CHANGED=0
			shift
			;;
		--dry-run)
			DRY_RUN=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			die "Option inconnue: $1"
			;;
	esac
done

case "$TARGET" in
	linux)
		DEFAULT_PRESET="MultiRobot"
		DEFAULT_CHANNEL="linux"
		EXECUTABLE_NAME="MutliplayerTemplate.x86_64"
		;;
	windows)
		DEFAULT_PRESET="Windows Desktop"
		DEFAULT_CHANNEL="windows"
		EXECUTABLE_NAME="MutliplayerTemplate.exe"
		;;
	*)
		die "--target doit etre linux ou windows"
		;;
esac

if [[ "$PRESET" == "MultiRobot" && "$TARGET" == "windows" ]]; then
	PRESET="$DEFAULT_PRESET"
fi
if [[ "$CHANNEL" == "linux" && "$TARGET" == "windows" ]]; then
	CHANNEL="$DEFAULT_CHANNEL"
fi

[[ -x "$GODOT_BIN" ]] || die "GODOT_BIN introuvable ou non executable: $GODOT_BIN"
command -v git >/dev/null 2>&1 || die "git est requis"

if [[ -z "$VERSION" ]]; then
	VERSION="$(git -C "$ROOT_DIR" describe --tags --always --dirty)"
fi

SAFE_VERSION="$(printf '%s' "$VERSION" | tr -c 'A-Za-z0-9._-' '-')"
BUILD_DIR="$BUILD_ROOT/$TARGET/$SAFE_VERSION"
EXPORT_PATH="$BUILD_DIR/$EXECUTABLE_NAME"

log "root=$ROOT_DIR"
log "target=$TARGET preset=$PRESET channel=$CHANNEL version=$VERSION"
log "build_dir=$BUILD_DIR"

if [[ "$RUN_TESTS" == "1" ]]; then
	run_cmd env HOME=/tmp XDG_DATA_HOME=/tmp "$GODOT_BIN" --headless --path "$ROOT_DIR" \
		-s addons/gut/gut_cmdln.gd -gdir=test -ginclude_subdirs -gexit
fi

if [[ "$DRY_RUN" != "1" ]]; then
	rm -rf "$BUILD_DIR"
	mkdir -p "$BUILD_DIR"
fi

run_cmd "$GODOT_BIN" --headless --path "$ROOT_DIR" --export-release "$PRESET" "$EXPORT_PATH"

if [[ "$TARGET" == "linux" && "$DRY_RUN" != "1" ]]; then
	chmod +x "$EXPORT_PATH"
	cat > "$BUILD_DIR/run.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "\$(dirname "\${BASH_SOURCE[0]}")"
./$EXECUTABLE_NAME "\$@"
EOF
	chmod +x "$BUILD_DIR/run.sh"
fi

if [[ "$PUBLISH" == "0" ]]; then
	log "Export termine: $BUILD_DIR"
	log "Publication ignoree. Ajoute --publish avec ITCH_TARGET=user/game pour publier."
	exit 0
fi

[[ -n "$ITCH_TARGET" ]] || die "ITCH_TARGET=user/game est requis pour --publish"
command -v "$BUTLER_BIN" >/dev/null 2>&1 || die "butler introuvable. Installe itch.io butler ou renseigne BUTLER_BIN."

BUTLER_ARGS=(push "$BUILD_DIR" "$ITCH_TARGET:$CHANNEL" --userversion "$VERSION")
if [[ "$IF_CHANGED" == "1" ]]; then
	BUTLER_ARGS+=(--if-changed)
fi
if [[ "$HIDDEN" == "1" ]]; then
	BUTLER_ARGS+=(--hidden)
fi

run_cmd "$BUTLER_BIN" "${BUTLER_ARGS[@]}"
log "Publication itch.io terminee: $ITCH_TARGET:$CHANNEL version=$VERSION"
