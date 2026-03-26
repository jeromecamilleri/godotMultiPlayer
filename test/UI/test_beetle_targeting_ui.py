#!/usr/bin/env python3
from __future__ import annotations

import atexit
import json
import os
import random
import shutil
import subprocess
import sys
import time
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]
OUT_DIR = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/tmp/beetle-targeting-ui")
OUT_DIR.mkdir(parents=True, exist_ok=True)
SUMMARY_PATH = OUT_DIR / "summary.txt"

for old_file in OUT_DIR.iterdir():
    if not old_file.is_file():
        continue
    if old_file.suffix.lower() in {".png", ".json", ".log", ".txt"}:
        old_file.unlink()

RUN_LOG_PATH = OUT_DIR / "run.log"
NATIVE_GODOT_PATH = Path("/dataSSD/Godot_v4.6.1-stable_linux.x86_64")
XVFB_DISPLAY = ":99"
RUNTIME_NAME = "MutliplayerTemplate (DEBUG)"
RUNTIME_SEARCH = "MutliplayerTemplate"

run_log = RUN_LOG_PATH.open("w", encoding="utf-8", buffering=1)
phase_lines: list[str] = []
launched_runtime_procs: list[subprocess.Popen[str]] = []
launched_runtime_window_ids: list[str] = []
launched_runtime_log_handles: list[object] = []
xvfb_log_handle = None
X11_ENV = dict(os.environ)
TEST_PORT = str(25000 + (os.getpid() % 10000) + random.randint(0, 999))


def log(message: str) -> None:
    print(message)
    print(message, file=run_log)


def phase(title: str, detail: str = "") -> None:
    line = f"[PHASE] {title}"
    if detail:
        line += f" | {detail}"
    phase_lines.append(line)
    log(line)


def write_summary() -> None:
    SUMMARY_PATH.write_text("\n".join(phase_lines) + "\n", encoding="utf-8")


def run_cmd(args: list[str], env: dict[str, str] | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, env=env or X11_ENV, text=True, capture_output=True, check=check)


def try_run_cmd(args: list[str], env: dict[str, str] | None = None) -> str:
    completed = subprocess.run(args, env=env or X11_ENV, text=True, capture_output=True)
    if completed.returncode != 0:
        return ""
    return completed.stdout.strip()


def search_windows(pattern: str) -> list[str]:
    output = try_run_cmd(["xdotool", "search", "--onlyvisible", "--name", pattern])
    return [line.strip() for line in output.splitlines() if line.strip()]


def window_name(window_id: str) -> str:
    return try_run_cmd(["xdotool", "getwindowname", window_id])


def runtime_window_ids() -> list[str]:
    return [window_id for window_id in search_windows(RUNTIME_SEARCH) if window_name(window_id) == RUNTIME_NAME]


def import_root(output_path: Path) -> None:
    run_cmd(["import", "-window", "root", str(output_path)])


def import_window(window_id: str, output_path: Path) -> None:
    run_cmd(["import", "-window", window_id, str(output_path)])


def display_geometry() -> tuple[int, int]:
    width_text, height_text = run_cmd(["xdotool", "getdisplaygeometry"]).stdout.split()
    return int(width_text), int(height_text)


def activate_window(window_id: str) -> None:
    run_cmd(["xdotool", "windowactivate", "--sync", window_id])
    run_cmd(["xdotool", "windowraise", window_id])


def place_window(window_id: str, x: int, y: int, width: int, height: int) -> None:
    activate_window(window_id)
    run_cmd(["xdotool", "windowsize", "--sync", window_id, str(width), str(height)])
    time.sleep(0.2)
    run_cmd(["xdotool", "windowmove", "--sync", window_id, str(x), str(y)])
    time.sleep(0.2)


def wait_for_runtime_windows(expected_count: int) -> list[str]:
    for _ in range(180):
        ids = runtime_window_ids()
        if len(ids) >= expected_count:
            return ids[-expected_count:]
        time.sleep(0.25)
    raise RuntimeError(f"expected {expected_count} runtime windows")


def wait_for_json(path: Path, timeout_sec: float = 30.0, poll_interval: float = 0.25) -> dict:
    deadline = time.monotonic() + timeout_sec
    while time.monotonic() < deadline:
        if path.exists():
            with path.open(encoding="utf-8") as f:
                return json.load(f)
        time.sleep(poll_interval)
    raise RuntimeError(f"sync file not found: {path}")


def dump_runtime_logs() -> None:
    for log_path in sorted(OUT_DIR.glob("godot_runtime_*.log")):
        try:
            content = log_path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        tail = "\n".join(content.splitlines()[-30:])
        if tail:
            log(f"===== tail:{log_path.name} =====")
            log(tail)
            log("===== end tail =====")


def cleanup() -> None:
    if phase_lines:
        write_summary()
    for window_id in launched_runtime_window_ids:
        run_cmd(["xdotool", "windowclose", window_id], check=False)
    time.sleep(0.8)
    for proc in launched_runtime_procs:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
    for handle in launched_runtime_log_handles:
        handle.close()
    subprocess.run(["pkill", "-f", "openbox"], check=False, capture_output=True, text=True)
    subprocess.run(["pkill", "-f", f"Xvfb {XVFB_DISPLAY}"], check=False, capture_output=True, text=True)
    if xvfb_log_handle is not None:
        xvfb_log_handle.close()
    run_log.close()


atexit.register(cleanup)


def start_xvfb() -> None:
    global xvfb_log_handle, X11_ENV
    xvfb_log_handle = (OUT_DIR / "xvfb.log").open("w", encoding="utf-8")
    subprocess.run(["pkill", "-f", f"Xvfb {XVFB_DISPLAY}"], check=False, capture_output=True, text=True)
    subprocess.run(["pkill", "-f", "openbox"], check=False, capture_output=True, text=True)
    time.sleep(0.4)
    subprocess.Popen(
        ["Xvfb", XVFB_DISPLAY, "-screen", "0", "1920x1080x24", "-ac", "-nolisten", "tcp"],
        stdout=xvfb_log_handle,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    X11_ENV = {
        **os.environ,
        "DISPLAY": XVFB_DISPLAY,
        "LIBGL_ALWAYS_SOFTWARE": "1",
        "UI_TEST_DISABLE_BEES": "1",
        "UI_TEST_SCENARIO": "beetle_targeting",
        "UI_TEST_SYNC_DIR": str(OUT_DIR),
        "UI_TEST_PORT": TEST_PORT,
    }
    X11_ENV.pop("XAUTHORITY", None)
    time.sleep(1.0)
    subprocess.Popen(
        ["openbox"],
        stdout=xvfb_log_handle,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
        env=X11_ENV,
    )
    time.sleep(1.0)
    phase("Xvfb prêt", f"display={XVFB_DISPLAY}")
    log(f"ui_test_port={TEST_PORT}")


def launch_runtime_instance(label: str, role: str) -> None:
    log_path = OUT_DIR / f"godot_runtime_{label}.log"
    log_handle = log_path.open("w", encoding="utf-8")
    launched_runtime_log_handles.append(log_handle)
    env = {
        **X11_ENV,
        "UI_TEST_INSTANCE_ROLE": role,
        "UI_TEST_AUTO_ROLE": "server" if role == "server" else "client",
    }
    cmd = [str(NATIVE_GODOT_PATH), "--rendering-driver", "opengl3", "--path", str(ROOT_DIR)]
    phase("Lancement Godot", f"instance={label} role={role}")
    log(f"launch_cmd[{label}]={' '.join(cmd)}")
    log(f"launch_role[{label}]={role}")
    log(f"launch_port[{label}]={TEST_PORT}")
    proc = subprocess.Popen(
        cmd,
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
        env=env,
        cwd=str(ROOT_DIR),
    )
    launched_runtime_procs.append(proc)


def main() -> int:
    start_xvfb()
    screen_w, screen_h = display_geometry()
    margin_x = 18
    margin_y = 72
    gap_x = 18
    gap_y = 18
    win_w = min(760, max(520, (screen_w - (margin_x * 2) - gap_x) // 2))
    win_h = min(460, max(380, (screen_h - margin_y - 120 - gap_y) // 2))
    positions = [
        (margin_x, margin_y),
        (margin_x + win_w + gap_x, margin_y),
        (margin_x, margin_y + win_h + gap_y),
        (margin_x + win_w + gap_x, margin_y + win_h + gap_y),
    ]

    launch_runtime_instance("1", "server")
    server_window_id = wait_for_runtime_windows(1)[0]
    place_window(server_window_id, positions[0][0], positions[0][1], win_w, win_h)
    phase("Démarrage auto serveur", "menu contourné via UI_TEST_AUTO_ROLE")
    time.sleep(1.2)

    launch_runtime_instance("2", "client_1")
    server_window_id, client_1_window_id = wait_for_runtime_windows(2)
    place_window(client_1_window_id, positions[1][0], positions[1][1], win_w, win_h)
    phase("Démarrage auto client 1", "menu contourné via UI_TEST_AUTO_ROLE")
    time.sleep(1.0)

    launch_runtime_instance("3", "client_2")
    server_window_id, client_1_window_id, client_2_window_id = wait_for_runtime_windows(3)
    place_window(client_2_window_id, positions[2][0], positions[2][1], win_w, win_h)
    phase("Démarrage auto client 2", "menu contourné via UI_TEST_AUTO_ROLE")
    time.sleep(1.0)

    launch_runtime_instance("4", "client_3")
    server_window_id, client_1_window_id, client_2_window_id, client_3_window_id = wait_for_runtime_windows(4)
    launched_runtime_window_ids[:] = [server_window_id, client_1_window_id, client_2_window_id, client_3_window_id]
    place_window(client_3_window_id, positions[3][0], positions[3][1], win_w, win_h)
    phase(
        "Fenêtres runtime détectées",
        "server=%s client_1=%s client_2=%s client_3=%s" % (server_window_id, client_1_window_id, client_2_window_id, client_3_window_id),
    )
    time.sleep(1.2)

    phase("Capture initiale", "01_before_beetle_targeting.png")
    import_root(OUT_DIR / "01_before_beetle_targeting.png")

    phase("Observation scarabées", "attente des fichiers de synchro gameplay")
    client_1_state = wait_for_json(OUT_DIR / "beetle_targeting_client_1.json", timeout_sec=35.0)
    client_2_state = wait_for_json(OUT_DIR / "beetle_targeting_client_2.json", timeout_sec=35.0)
    client_3_state = wait_for_json(OUT_DIR / "beetle_targeting_client_3.json", timeout_sec=35.0)

    time.sleep(0.8)
    import_window(server_window_id, OUT_DIR / "02_server_beetle_targeting.png")
    import_window(client_1_window_id, OUT_DIR / "03_client_1_beetle_targeting.png")
    import_window(client_2_window_id, OUT_DIR / "04_client_2_beetle_targeting.png")
    import_window(client_3_window_id, OUT_DIR / "05_client_3_beetle_targeting.png")
    import_root(OUT_DIR / "06_after_beetle_targeting.png")

    for client_state in [client_1_state, client_2_state, client_3_state]:
        if int(client_state.get("participant_count", 0)) != 4:
            raise AssertionError(f"Le scénario devait tourner avec 4 participants: {client_state}")
        if int(client_state.get("player_count", 0)) != 3:
            raise AssertionError(f"Le host ne spawnant pas de joueur local, chaque client doit observer 3 joueurs actifs: {client_state}")
        if int(client_state.get("beetle_count", -1)) != 3:
            raise AssertionError(f"Chaque client doit observer 3 scarabées: {client_state}")
        if int(client_state.get("unique_assigned_target_count", 0)) != 3:
            raise AssertionError(f"Les 3 scarabées doivent viser 3 joueurs distincts: {client_state}")
        if int(client_state.get("unique_current_target_count", 0)) != 3:
            raise AssertionError(f"Les 3 scarabées doivent effectivement poursuivre 3 joueurs distincts: {client_state}")
        player_ids = set(int(v) for v in client_state.get("player_peer_ids", []))
        assigned_ids = set(int(v) for v in client_state.get("assigned_target_peer_ids", []))
        if not assigned_ids.issubset(player_ids):
            raise AssertionError(f"Les cibles assignées doivent être des joueurs actifs: {client_state}")

    phase("Assertions", "3 scarabées pour 4 joueurs, avec 3 cibles distinctes")
    log(f"client_1_state={client_1_state}")
    log(f"client_2_state={client_2_state}")
    log(f"client_3_state={client_3_state}")
    phase("Fin du scénario", f"captures={OUT_DIR}")
    write_summary()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        log(f"error: {exc}")
        dump_runtime_logs()
        sys.exit(1)
