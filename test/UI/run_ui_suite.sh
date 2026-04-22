#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

PROFILE="smoke"
MODE="profile"
declare -a CHANGED_FILES=()

usage() {
  cat <<'EOF'
Usage:
  test/UI/run_ui_suite.sh [--profile smoke|full]
  test/UI/run_ui_suite.sh --changed <file1> [file2 ...]

Options:
  --profile smoke|full   Run predefined UI suites (default: smoke)
  --changed <files...>   Select a reduced suite from changed paths
EOF
}

while (($#)); do
  case "$1" in
    --profile)
      PROFILE="${2:-}"
      shift 2
      ;;
    --changed)
      MODE="changed"
      shift
      while (($#)); do
        CHANGED_FILES+=("$1")
        shift
      done
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 2
      ;;
  esac
done

declare -a TESTS=()
declare -A ADDED=()

add_test() {
  local test_path="$1"
  if [[ -n "${ADDED[$test_path]:-}" ]]; then
    return
  fi
  ADDED[$test_path]=1
  TESTS+=("$test_path")
}

add_smoke_suite() {
  add_test "test/UI/test_inventory_chest_ui.sh"
  add_test "test/UI/test_portal_unlock_ui.sh"
  add_test "test/UI/test_portal_progression_breche_ui.sh"
  add_test "test/UI/test_cube_mission_ui.sh"
}

add_full_suite() {
  add_test "test/UI/test_inventory_chest_ui.sh"
  add_test "test/UI/test_inventory_player_proximity_ui.sh"
  add_test "test/UI/test_inventory_transfer_multiplayer_ui.sh"
  add_test "test/UI/test_late_join_bomb_wood_ui.sh"
  add_test "test/UI/test_portal_unlock_ui.sh"
  add_test "test/UI/test_portal_logistics_ui.sh"
  add_test "test/UI/test_portal_progression_ui.sh"
  add_test "test/UI/test_cube_mission_ui.sh"
  add_test "test/UI/test_cube_mission_lock_ui.sh"
  add_test "test/UI/test_beetle_targeting_ui.sh"
  add_test "test/UI/test_beetle_door_charge_ui.sh"
}

if [[ "$MODE" == "profile" ]]; then
  case "$PROFILE" in
    smoke)
      add_smoke_suite
      ;;
    full)
      add_full_suite
      ;;
    *)
      echo "Unknown profile: $PROFILE" >&2
      usage
      exit 2
      ;;
  esac
else
  if ((${#CHANGED_FILES[@]} == 0)); then
    echo "--changed requires at least one file path" >&2
    exit 2
  fi

  for path in "${CHANGED_FILES[@]}"; do
    case "$path" in
      inventory/*|ui/inventory_*|ui/*inventory*)
        add_test "test/UI/test_inventory_chest_ui.sh"
        add_test "test/UI/test_inventory_transfer_multiplayer_ui.sh"
        add_test "test/UI/test_inventory_player_proximity_ui.sh"
        ;;
      main/rigid_body_3d.gd|main/cube_activator.gd|player/components/player_interactions.gd|main/mission_cube_*|levels/zones/finale/*)
        add_test "test/UI/test_cube_mission_ui.sh"
        add_test "test/UI/test_cube_mission_lock_ui.sh"
        add_test "test/UI/test_portal_progression_reactor_ui.sh"
        ;;
      levels/portal/*|main/match_director.gd|main/ui_test_scenario_server_pilot.gd|levels/hub/*|levels/zones/scierie/*|levels/zones/verger/*)
        add_test "test/UI/test_portal_unlock_ui.sh"
        add_test "test/UI/test_portal_progression_breche_ui.sh"
        add_test "test/UI/test_portal_progression_reactor_ui.sh"
        ;;
      enemies/beetle_*|enemies/bee_*|enemies/enemy_*|main/mission_*enemies*|levels/zones/verger/*enemies*|levels/zones/finale/*enemies*)
        add_test "test/UI/test_beetle_targeting_ui.sh"
        add_test "test/UI/test_beetle_door_charge_ui.sh"
        ;;
      main/bomb_door.gd|environment/box/*)
        add_test "test/UI/test_portal_progression_reactor_ui.sh"
        add_test "test/UI/test_cube_mission_ui.sh"
        ;;
      player/*|main/player_spawner.gd|main/connection.gd|ui/ui.gd|ui/ui.tscn)
        add_smoke_suite
        ;;
    esac
  done

  if ((${#TESTS[@]} == 0)); then
    add_smoke_suite
  fi
fi

echo "[UI SUITE] mode=${MODE} profile=${PROFILE} count=${#TESTS[@]}"
for test_script in "${TESTS[@]}"; do
  echo "RUN:${test_script}"
  bash "${test_script}"
done
