#!/usr/bin/env python3
from __future__ import annotations

import atexit
import json
import os
import random
import subprocess
import sys
import time
from pathlib import Path

from godot_runtime_config import NATIVE_GODOT_PATH, RENDERING_DRIVER


ROOT_DIR = Path(__file__).resolve().parents[2]
OUT_DIR = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/tmp/portal-unlock-ui")
OUT_DIR.mkdir(parents=True, exist_ok=True)
SUMMARY_PATH = OUT_DIR / "summary.txt"

for old_file in OUT_DIR.iterdir():
    if not old_file.is_file():
        continue
    if old_file.suffix.lower() in {".png", ".json", ".log", ".txt"}:
        old_file.unlink()

RUN_LOG_PATH = OUT_DIR / "run.log"
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
TEST_PORT = str(26000 + (os.getpid() % 10000) + random.randint(0, 999))


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
    for _ in range(20):
        completed = subprocess.run(["xdotool", "getdisplaygeometry"], env=X11_ENV, text=True, capture_output=True)
        if completed.returncode == 0:
            width_text, height_text = completed.stdout.split()
            return int(width_text), int(height_text)
        time.sleep(0.2)
    raise RuntimeError("xdotool getdisplaygeometry indisponible sur le display Xvfb")


def activate_window(window_id: str) -> None:
    run_cmd(["xdotool", "windowactivate", "--sync", window_id], check=False)
    run_cmd(["xdotool", "windowraise", window_id], check=False)


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


def wait_for_json(path: Path, timeout_sec: float = 35.0, poll_interval: float = 0.25) -> dict:
    deadline = time.monotonic() + timeout_sec
    while time.monotonic() < deadline:
        if path.exists():
            try:
                with path.open(encoding="utf-8") as f:
                    return json.load(f)
            except (json.JSONDecodeError, OSError):
                pass
        time.sleep(poll_interval)
    raise RuntimeError(f"sync file not found: {path}")


def wait_for_portal_unlock_states(timeout_sec: float = 40.0, poll_interval: float = 0.25) -> tuple[dict, dict, dict]:
    server_path = OUT_DIR / "portal_unlock_server.json"
    client_a_path = OUT_DIR / "portal_unlock_client_a.json"
    client_b_path = OUT_DIR / "portal_unlock_client_b.json"
    deadline = time.monotonic() + timeout_sec
    latest: tuple[dict, dict, dict] | None = None
    while time.monotonic() < deadline:
        if server_path.exists() and client_a_path.exists() and client_b_path.exists():
            try:
                server_state = json.loads(server_path.read_text(encoding="utf-8"))
                client_a_state = json.loads(client_a_path.read_text(encoding="utf-8"))
                client_b_state = json.loads(client_b_path.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, OSError):
                time.sleep(poll_interval)
                continue
            latest = (server_state, client_a_state, client_b_state)
            states = [server_state, client_a_state, client_b_state]
            if all(bool(state.get("portal_breche_active", False)) for state in states) and all(
                not bool(state.get("portal_reactor_active", False)) for state in states
            ):
                return latest
        time.sleep(poll_interval)
    if latest is not None:
        return latest
    raise RuntimeError(f"sync file not found: {server_path}")


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
        "UI_TEST_DISABLE_BEETLES": "1",
        "UI_TEST_SCENARIO": "portal_unlock",
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
    cmd = [str(NATIVE_GODOT_PATH), "--rendering-driver", RENDERING_DRIVER, "--path", str(ROOT_DIR)]
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
    win_w = min(760, max(520, (screen_w - (margin_x * 2) - gap_x) // 2))
    win_h = min(460, max(380, (screen_h - margin_y - 120) // 2))
    positions = [
        (margin_x, margin_y),
        (margin_x + win_w + gap_x, margin_y),
        (margin_x, margin_y + win_h + gap_x),
    ]

    launch_runtime_instance("1", "server")
    server_window_id = wait_for_runtime_windows(1)[0]
    place_window(server_window_id, positions[0][0], positions[0][1], win_w, win_h)
    phase("Démarrage auto serveur", "menu contourné via UI_TEST_AUTO_ROLE")
    time.sleep(1.2)

    launch_runtime_instance("2", "client_a")
    server_window_id, client_a_window_id = wait_for_runtime_windows(2)
    place_window(client_a_window_id, positions[1][0], positions[1][1], win_w, win_h)
    phase("Démarrage auto client A", "menu contourné via UI_TEST_AUTO_ROLE")
    time.sleep(1.0)

    launch_runtime_instance("3", "client_b")
    server_window_id, client_a_window_id, client_b_window_id = wait_for_runtime_windows(3)
    launched_runtime_window_ids[:] = [server_window_id, client_a_window_id, client_b_window_id]
    place_window(client_b_window_id, positions[2][0], positions[2][1], win_w, win_h)
    phase("Fenêtres runtime détectées", f"server={server_window_id} client_a={client_a_window_id} client_b={client_b_window_id}")
    time.sleep(1.2)

    phase("Capture initiale", "01_before_portal_unlock.png")
    import_root(OUT_DIR / "01_before_portal_unlock.png")

    phase("Collecte et dépôt", "attente du déverrouillage du portail Breche")
    server_state, client_a_state, client_b_state = wait_for_portal_unlock_states(timeout_sec=40.0)

    time.sleep(0.8)
    import_window(server_window_id, OUT_DIR / "02_server_portal_unlock.png")
    import_window(client_a_window_id, OUT_DIR / "03_client_a_portal_unlock.png")
    import_window(client_b_window_id, OUT_DIR / "04_client_b_portal_unlock.png")
    import_root(OUT_DIR / "05_after_portal_unlock.png")

    for state in [server_state, client_a_state, client_b_state]:
        if not bool(state.get("portal_breche_active", False)):
            raise AssertionError(f"Le portail Breche devait être actif: {state}")
        if bool(state.get("portal_reactor_active", True)):
            raise AssertionError(f"Le portail Reactor ne devait pas encore être actif: {state}")

    if int(server_state.get("chest_wood_delivered", 0)) < 4:
        raise AssertionError(f"Le serveur doit voir au moins le quota de bois livré: {server_state}")
    if int(server_state.get("chest_apple_delivered", 0)) < 2:
        raise AssertionError(f"Le serveur doit voir au moins le quota de pommes livré: {server_state}")

    phase("Assertions", "le coffre déverrouille le portail Breche sur toutes les vues")
    log(f"server_state={server_state}")
    log(f"client_a_state={client_a_state}")
    log(f"client_b_state={client_b_state}")
    phase("Fin du scénario", f"captures={OUT_DIR}")
    write_summary()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        phase("Échec", str(exc))
        dump_runtime_logs()
        write_summary()
        raise
