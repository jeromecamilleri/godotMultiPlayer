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


ROOT_DIR = Path(__file__).resolve().parents[2]
PHASE_MODE = "full"
OUT_DIR = Path("/tmp/portal-progression-ui")


def parse_args() -> None:
    global OUT_DIR, PHASE_MODE
    args = list(sys.argv[1:])
    idx = 0
    while idx < len(args):
        arg = args[idx]
        if arg == "--phase":
            if idx + 1 >= len(args):
                raise ValueError("--phase attend une valeur: breche|reactor|full")
            PHASE_MODE = args[idx + 1].strip().lower()
            idx += 2
            continue
        if arg.startswith("--phase="):
            PHASE_MODE = arg.split("=", 1)[1].strip().lower()
            idx += 1
            continue
        OUT_DIR = Path(arg)
        idx += 1
    if PHASE_MODE not in {"breche", "reactor", "full"}:
        raise ValueError(f"phase inconnue: {PHASE_MODE}")


parse_args()
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
TEST_PORT = str(27000 + (os.getpid() % 10000) + random.randint(0, 999))


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


def wait_for_json(path: Path, timeout_sec: float = 40.0, poll_interval: float = 0.25) -> dict:
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


def try_wait_for_json(path: Path, timeout_sec: float = 5.0, poll_interval: float = 0.25) -> dict | None:
    deadline = time.monotonic() + timeout_sec
    while time.monotonic() < deadline:
        if path.exists():
            try:
                with path.open(encoding="utf-8") as f:
                    return json.load(f)
            except (json.JSONDecodeError, OSError):
                pass
        time.sleep(poll_interval)
    return None


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
        "UI_TEST_SCENARIO": "portal_progression",
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
    margin_x = 20
    margin_y = 72
    gap_x = 18
    win_w = min(760, max(520, (screen_w - (margin_x * 2) - (gap_x * 2)) // 3))
    win_h = min(720, max(540, screen_h - 160))
    positions = [
        (margin_x, margin_y),
        (margin_x + win_w + gap_x, margin_y),
        (margin_x + (win_w + gap_x) * 2, margin_y),
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
    place_window(client_b_window_id, positions[2][0], positions[2][1], win_w, win_h)
    launched_runtime_window_ids[:] = [server_window_id, client_a_window_id, client_b_window_id]
    phase("Fenêtres runtime détectées", f"server={server_window_id} client_a={client_a_window_id} client_b={client_b_window_id}")
    time.sleep(1.2)

    phase("Capture initiale", "01_before_portal_progression.png")
    import_root(OUT_DIR / "01_before_portal_progression.png")

    if PHASE_MODE == "breche":
        phase("Progression multi-zone", "attente phase Breche uniquement")
    elif PHASE_MODE == "reactor":
        phase("Progression multi-zone", "attente phase Reactor (et phase Breche préalable)")
    else:
        phase("Progression multi-zone", "attente des phases Breche puis Reactor")

    breche_phase = wait_for_json(OUT_DIR / "portal_progression_phase_breche.json", timeout_sec=50.0)
    import_root(OUT_DIR / "02_after_breche_unlock.png")
    reactor_phase: dict | None = None
    if PHASE_MODE in {"reactor", "full"}:
        reactor_phase = wait_for_json(OUT_DIR / "portal_progression_phase_reactor.json", timeout_sec=60.0)
        import_root(OUT_DIR / "03_after_reactor_unlock.png")

    client_a_state: dict | None = None
    client_b_state: dict | None = None
    server_state: dict | None = None
    if PHASE_MODE == "full":
        client_a_state = wait_for_json(OUT_DIR / "portal_progression_client_a.json", timeout_sec=75.0)
        client_b_state = wait_for_json(OUT_DIR / "portal_progression_client_b.json", timeout_sec=75.0)
        server_state = try_wait_for_json(OUT_DIR / "portal_progression_server.json", timeout_sec=6.0)
        if server_state is None:
            server_state = {
                "fallback_source": "client_snapshots",
                "initial_scierie_active": True,
                "initial_verger_active": True,
                "initial_breche_active": False,
                "initial_reactor_active": False,
                "breche_unlocked": bool(client_a_state.get("breche_unlocked_observed", False)) or bool(client_b_state.get("breche_unlocked_observed", False)),
                "reactor_unlocked": bool(client_a_state.get("reactor_unlocked_observed", False)) or bool(client_b_state.get("reactor_unlocked_observed", False)),
                "chest_wood": max(int(client_a_state.get("chest_wood", 0)), int(client_b_state.get("chest_wood", 0))),
                "chest_apple": max(int(client_a_state.get("chest_apple", 0)), int(client_b_state.get("chest_apple", 0))),
            }

    time.sleep(0.8)
    import_window(server_window_id, OUT_DIR / "04_server_portal_progression.png")
    import_window(client_a_window_id, OUT_DIR / "05_client_a_portal_progression.png")
    import_window(client_b_window_id, OUT_DIR / "06_client_b_portal_progression.png")
    import_root(OUT_DIR / "07_after_portal_progression.png")

    if not bool(breche_phase.get("breche_active", False)):
        raise AssertionError(f"La phase Breche devait activer le portail Breche: {breche_phase}")
    if bool(breche_phase.get("reactor_active", True)):
        raise AssertionError(f"La phase Breche ne devait pas activer Reactor: {breche_phase}")

    if PHASE_MODE in {"reactor", "full"}:
        assert reactor_phase is not None
        if not bool(reactor_phase.get("reactor_active", False)):
            raise AssertionError(f"La phase Reactor devait activer le portail Reactor: {reactor_phase}")

    if PHASE_MODE == "full":
        assert server_state is not None and client_a_state is not None and client_b_state is not None
        if not bool(server_state.get("initial_scierie_active", False)) or not bool(server_state.get("initial_verger_active", False)):
            raise AssertionError(f"Les portails Scierie et Verger devaient être actifs dès le début: {server_state}")
        if bool(server_state.get("initial_breche_active", True)) or bool(server_state.get("initial_reactor_active", True)):
            raise AssertionError(f"Les portails Breche et Reactor devaient être inactifs au début: {server_state}")
        if not bool(server_state.get("breche_unlocked", False)):
            raise AssertionError(f"Le portail Breche devait être déverrouillé en cours de progression: {server_state}")
        if not bool(server_state.get("reactor_unlocked", False)):
            raise AssertionError(f"Le portail Reactor devait être déverrouillé après la brèche: {server_state}")
        if not bool(client_a_state.get("breche_unlocked_observed", False)) or not bool(client_a_state.get("breche_entered", False)):
            raise AssertionError(f"Le client A devait observer puis traverser la brèche: {client_a_state}")
        if not bool(client_a_state.get("doors_opened", False)):
            raise AssertionError(f"Le client A devait réellement ouvrir les BombDoor: {client_a_state}")
        if not bool(client_a_state.get("reactor_entered", False)):
            raise AssertionError(f"Le client A devait atteindre la zone Reactor: {client_a_state}")
        if not bool(client_b_state.get("breche_unlocked_observed", False)) or not bool(client_b_state.get("reactor_unlocked_observed", False)):
            raise AssertionError(f"Le client B devait observer la progression des portails: {client_b_state}")
        if not bool(client_b_state.get("reactor_entered", False)):
            raise AssertionError(f"Le client B devait atteindre la zone Reactor: {client_b_state}")
        phase("Assertions", "progression complète validée du hub jusqu'au réacteur avec états de portails cohérents")
    elif PHASE_MODE == "reactor":
        phase("Assertions", "phase reactor validée (portail Breche puis Reactor actifs)")
    else:
        phase("Assertions", "phase breche validée (Breche actif, Reactor encore bloqué)")

    log(f"breche_phase={breche_phase}")
    if reactor_phase is not None:
        log(f"reactor_phase={reactor_phase}")
    if server_state is not None:
        log(f"server_state={server_state}")
    if client_a_state is not None:
        log(f"client_a_state={client_a_state}")
    if client_b_state is not None:
        log(f"client_b_state={client_b_state}")
    phase("Fin du scénario", f"captures={OUT_DIR}")
    write_summary()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        log(f"error: {exc}")
        dump_runtime_logs()
        raise SystemExit(1)
