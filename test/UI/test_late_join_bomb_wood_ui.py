#!/usr/bin/env python3
from __future__ import annotations

import atexit
import json
import os
import shutil
import subprocess
import sys
import time
from collections import deque
from pathlib import Path

from PIL import Image


ROOT_DIR = Path(__file__).resolve().parents[2]
OUT_DIR = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/tmp/late-join-bomb-wood-ui")
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


def window_geometry(window_id: str) -> dict[str, int]:
    output = run_cmd(["xdotool", "getwindowgeometry", "--shell", window_id]).stdout
    result: dict[str, int] = {}
    for line in output.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if value.isdigit():
            result[key] = int(value)
    return result


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


def click_window(window_id: str, x: int, y: int) -> None:
    geometry = window_geometry(window_id)
    abs_x = geometry["X"] + x
    abs_y = geometry["Y"] + y
    activate_window(window_id)
    run_cmd(["xdotool", "mousemove", "--sync", str(abs_x), str(abs_y), "click", "1"])


def menu_visible_in_window_capture(image_path: Path) -> bool:
    img = Image.open(image_path).convert("RGB")
    w, h = img.size
    x0 = int(w * 0.30)
    x1 = int(w * 0.70)
    y0 = int(h * 0.35)
    y1 = int(h * 0.62)
    bright = 0
    mid_dark = 0
    dark_rows: list[bool] = []
    for y in range(y0, y1):
        row_dark = 0
        for x in range(x0, x1):
            r, g, b = img.getpixel((x, y))
            avg = (r + g + b) / 3.0
            if avg > 180:
                bright += 1
            elif 35 < avg < 95:
                mid_dark += 1
            if avg < 70:
                row_dark += 1
        dark_rows.append(row_dark > int((x1 - x0) * 0.45))
    bands = 0
    in_band = False
    for is_dark in dark_rows:
        if is_dark and not in_band:
            bands += 1
            in_band = True
        elif not is_dark:
            in_band = False
    return bright > 300 and mid_dark > 12000 and bands >= 1


def detect_menu_button_centers(image_path: Path) -> tuple[tuple[int, int], tuple[int, int]]:
    img = Image.open(image_path).convert("RGB")
    w, h = img.size
    x0 = int(w * 0.20)
    x1 = int(w * 0.80)
    y0 = int(h * 0.20)
    y1 = int(h * 0.75)
    mask = [[False] * (x1 - x0) for _ in range(y1 - y0)]
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b = img.getpixel((x, y))
            if (r + g + b) / 3.0 < 34:
                mask[y - y0][x - x0] = True
    visited: set[tuple[int, int]] = set()
    components: list[tuple[int, int, int, int, int]] = []
    height = len(mask)
    width = len(mask[0]) if height else 0
    for yy in range(height):
        for xx in range(width):
            if not mask[yy][xx] or (xx, yy) in visited:
                continue
            queue = deque([(xx, yy)])
            visited.add((xx, yy))
            points: list[tuple[int, int]] = []
            while queue:
                cx, cy = queue.popleft()
                points.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < width and 0 <= ny < height and mask[ny][nx] and (nx, ny) not in visited:
                        visited.add((nx, ny))
                        queue.append((nx, ny))
            if len(points) < 200:
                continue
            xs = [p[0] for p in points]
            ys = [p[1] for p in points]
            components.append((len(points), min(xs) + x0, max(xs) + x0, min(ys) + y0, max(ys) + y0))
    components.sort(key=lambda item: item[3])
    upper = components[0]
    lower = components[1]
    return ((upper[1] + upper[2]) // 2, (upper[3] + upper[4]) // 2), ((lower[1] + lower[2]) // 2, (lower[3] + lower[4]) // 2)


def wait_for_menu(window_id: str, probe_name: str, attempts: int = 30, delay: float = 0.25) -> Path:
    probe_path = OUT_DIR / f"{probe_name}_probe.png"
    for attempt in range(attempts):
        import_window(window_id, probe_path)
        visible = menu_visible_in_window_capture(probe_path)
        log(f"{probe_name}_probe[{attempt}]={1 if visible else 0}")
        if visible:
            ready = OUT_DIR / f"{probe_name}_ready.png"
            shutil.copy2(probe_path, ready)
            return ready
        time.sleep(delay)
    raise RuntimeError(f"menu not detected for {probe_name}")


def click_detected_menu_button(window_id: str, probe_image: Path, role: str, output_prefix: str) -> None:
    server_center, client_center = detect_menu_button_centers(probe_image)
    target = server_center if role == "server" else client_center
    log(f"{output_prefix}_button_center={target}")
    click_window(window_id, *target)


def wait_for_menu_to_disappear(window_id: str, output_prefix: str, attempts: int = 20, delay: float = 0.25) -> None:
    probe_path = OUT_DIR / f"{output_prefix}_after_click_probe.png"
    for attempt in range(attempts):
        import_window(window_id, probe_path)
        still_visible = menu_visible_in_window_capture(probe_path)
        log(f"{output_prefix}_menu_gone_probe[{attempt}]={0 if still_visible else 1}")
        if not still_visible:
            shutil.copy2(probe_path, OUT_DIR / f"{output_prefix}_after_click_ready.png")
            return
        time.sleep(delay)
    if probe_path.exists():
        shutil.copy2(probe_path, OUT_DIR / f"{output_prefix}_after_click_timeout.png")
    raise RuntimeError(f"menu still visible for {output_prefix}")


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
        "UI_TEST_SCENARIO": "late_join_bomb_wood",
        "UI_TEST_SYNC_DIR": str(OUT_DIR),
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


def launch_runtime_instance(label: str, role: str) -> None:
    log_path = OUT_DIR / f"godot_runtime_{label}.log"
    log_handle = log_path.open("w", encoding="utf-8")
    launched_runtime_log_handles.append(log_handle)
    env = {**X11_ENV, "UI_TEST_INSTANCE_ROLE": role}
    cmd = [str(NATIVE_GODOT_PATH), "--rendering-driver", "opengl3", "--path", str(ROOT_DIR)]
    phase("Lancement Godot", f"instance={label} role={role}")
    log(f"launch_cmd[{label}]={' '.join(cmd)}")
    log(f"launch_role[{label}]={role}")
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


def wait_for_runtime_windows(expected_count: int) -> list[str]:
    for _ in range(160):
        ids = runtime_window_ids()
        if len(ids) >= expected_count:
            return ids[-expected_count:]
        time.sleep(0.25)
    raise RuntimeError(f"expected {expected_count} runtime windows")


def wait_for_json(path: Path, timeout_sec: float = 20.0, poll_interval: float = 0.25) -> dict:
    deadline = time.monotonic() + timeout_sec
    while time.monotonic() < deadline:
        if path.exists():
            with path.open(encoding="utf-8") as f:
                return json.load(f)
        time.sleep(poll_interval)
    raise RuntimeError(f"sync file not found: {path}")


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


def main() -> int:
    start_xvfb()
    screen_w, screen_h = display_geometry()
    margin_x = 18
    margin_y = 72
    gap = 18
    available_w = screen_w - (margin_x * 2) - (gap * 2)
    win_w = min(600, max(500, available_w // 3))
    win_h = min(720, max(520, screen_h - margin_y - 140))
    x_positions = [margin_x, margin_x + win_w + gap, margin_x + (win_w + gap) * 2]

    launch_runtime_instance("1", "server")
    server_window_id = wait_for_runtime_windows(1)[0]
    place_window(server_window_id, x_positions[0], margin_y, win_w, win_h)
    server_ready = wait_for_menu(server_window_id, "02_server_menu")
    phase("Sélection du serveur", "fenêtre gauche")
    click_detected_menu_button(server_window_id, server_ready, "server", "02_server")
    wait_for_menu_to_disappear(server_window_id, "02_server")
    time.sleep(1.2)

    launch_runtime_instance("2", "client_a")
    server_window_id, client_a_window_id = wait_for_runtime_windows(2)
    place_window(client_a_window_id, x_positions[1], margin_y, win_w, win_h)
    client_a_ready = wait_for_menu(client_a_window_id, "03_client_a_menu")
    phase("Sélection du client A", "fenêtre centre")
    click_detected_menu_button(client_a_window_id, client_a_ready, "client", "03_client_a")
    wait_for_menu_to_disappear(client_a_window_id, "03_client_a")
    launched_runtime_window_ids[:] = [server_window_id, client_a_window_id]

    phase("Client A ouvre le mur puis ramasse le bois", "attente du scénario déterministe")
    client_a_state = wait_for_json(OUT_DIR / "late_join_client_a.json", timeout_sec=18.0)
    import_root(OUT_DIR / "04_after_client_a_actions.png")
    if not bool(client_a_state.get("door_open")):
        raise AssertionError(f"Client A devait voir le mur ouvert: {client_a_state}")
    if bool(client_a_state.get("wood_pickable")):
        raise AssertionError(f"Client A devait avoir ramassé le bois: {client_a_state}")
    if int(client_a_state.get("player_wood_count", 0)) <= 0:
        raise AssertionError(f"Client A devait avoir du bois dans le sac: {client_a_state}")

    launch_runtime_instance("3", "client_b")
    server_window_id, client_a_window_id, client_b_window_id = wait_for_runtime_windows(3)
    launched_runtime_window_ids[:] = [server_window_id, client_a_window_id, client_b_window_id]
    place_window(client_b_window_id, x_positions[2], margin_y, win_w, win_h)
    client_b_ready = wait_for_menu(client_b_window_id, "05_client_b_menu")
    phase("Sélection du client B", "late join après bombe et pickup")
    click_detected_menu_button(client_b_window_id, client_b_ready, "client", "05_client_b")
    wait_for_menu_to_disappear(client_b_window_id, "05_client_b")

    phase("Client B rejoint tard", "vérification état persistant")
    client_b_state = wait_for_json(OUT_DIR / "late_join_client_b.json", timeout_sec=10.0)
    import_root(OUT_DIR / "06_after_client_b_join.png")
    if not bool(client_b_state.get("door_open")):
        raise AssertionError(f"Client B devait voir le mur déjà ouvert: {client_b_state}")
    if bool(client_b_state.get("wood_pickable")):
        raise AssertionError(f"Client B ne devait plus voir le bois ramassable: {client_b_state}")

    phase("Assertions", "late join cohérent pour mur et bois")
    log(f"client_a_state={client_a_state}")
    log(f"client_b_state={client_b_state}")
    phase("Fin du scénario", f"captures={OUT_DIR}")
    write_summary()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        log(f"error: {exc}")
        sys.exit(1)
