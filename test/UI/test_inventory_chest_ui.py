#!/usr/bin/env python3
from __future__ import annotations

import atexit
from collections import deque
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image


ROOT_DIR = Path(__file__).resolve().parents[2]
OUT_DIR = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/tmp/inventory-ui-x11")
OUT_DIR.mkdir(parents=True, exist_ok=True)
SUMMARY_PATH = OUT_DIR / "summary.txt"

for old_file in OUT_DIR.iterdir():
    if old_file.is_file() and (
        old_file.suffix.lower() == ".png" or old_file.name in {"run.log", "godot_runtime.log", "menu_probe.png", "summary.txt"}
    ):
        old_file.unlink()

RUN_LOG_PATH = OUT_DIR / "run.log"
NATIVE_GODOT_PATH = Path("/dataSSD/Godot_v4.6.1-stable_linux.x86_64")
USE_XVFB = True
XVFB_DISPLAY = ":99"

DISPLAY_VALUE = os.environ.get("DISPLAY", ":0")
XAUTHORITY_VALUE = os.environ.get("XAUTHORITY", "/run/user/1000/gdm/Xauthority")
X11_ENV = {**os.environ, "DISPLAY": DISPLAY_VALUE, "XAUTHORITY": XAUTHORITY_VALUE}

EDITOR_NAME = "ui.tscn - MutliplayerTemplate - Godot Engine"
EDITOR_SEARCH = "Godot Engine"
RUNTIME_NAME = "MutliplayerTemplate (DEBUG)"
RUNTIME_SEARCH = "MutliplayerTemplate"

run_log = RUN_LOG_PATH.open("w", encoding="utf-8", buffering=1)
launched_runtime_procs: list[subprocess.Popen[str]] = []
launched_runtime_window_ids: list[str] = []
launched_runtime_log_handles: list[object] = []
xvfb_proc: subprocess.Popen[str] | None = None
openbox_proc: subprocess.Popen[str] | None = None
xvfb_log_handle = None
phase_lines: list[str] = []
AUTO_ROLE_BOOT = True


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


def run_cmd(args: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, env=X11_ENV, text=True, capture_output=True, check=check)


def try_run_cmd(args: list[str]) -> str:
    completed = subprocess.run(args, env=X11_ENV, text=True, capture_output=True)
    if completed.returncode != 0:
        return ""
    return completed.stdout.strip()


def xdotool(*args: str, check: bool = True) -> str:
    return run_cmd(["xdotool", *args], check=check).stdout.strip()


def log_process_snapshot() -> None:
    completed = subprocess.run(
        ["ps", "-ef"],
        text=True,
        capture_output=True,
        check=False,
    )
    log("process_snapshot_begin")
    for line in completed.stdout.splitlines():
        if any(token in line for token in ("Xvfb", "openbox", "Godot_v4.6.1-stable_linux.x86_64", "godot-multiplayer")):
            log(line)
    log("process_snapshot_end")


def import_window(window_id: str, output_path: Path) -> None:
    run_cmd(["import", "-window", window_id, str(output_path)])


def import_root(output_path: Path) -> None:
    run_cmd(["import", "-window", "root", str(output_path)])


def search_windows(pattern: str) -> list[str]:
    output = try_run_cmd(["xdotool", "search", "--onlyvisible", "--name", pattern])
    return [line.strip() for line in output.splitlines() if line.strip()]


def window_name(window_id: str) -> str:
    return try_run_cmd(["xdotool", "getwindowname", window_id])


def latest_window_id(pattern: str, expected_name: str | None = None) -> str | None:
    matches: list[str] = []
    for window_id in search_windows(pattern):
        if expected_name is None or window_name(window_id) == expected_name:
            matches.append(window_id)
    return matches[-1] if matches else None


def visible_godot_windows() -> list[tuple[str, str]]:
    return [(window_id, window_name(window_id)) for window_id in search_windows(RUNTIME_SEARCH)]


def dump_visible_godot_windows() -> None:
    log("visible_godot_windows:")
    windows = visible_godot_windows()
    if not windows:
        log("  (none)")
        return
    for window_id, name in windows:
        log(f"  id={window_id} name={name}")


def stale_runtime_pids() -> list[int]:
    completed = subprocess.run(["ps", "-eo", "pid,args"], text=True, capture_output=True)
    if completed.returncode != 0:
        return []
    pids: list[int] = []
    for line in completed.stdout.splitlines()[1:]:
        match = re.match(r"^\s*(\d+)\s+(.*)$", line)
        if not match:
            continue
        pid = int(match.group(1))
        cmdline = match.group(2)
        if "--editor" in cmdline:
            continue
        is_project_runtime = f"--path {ROOT_DIR}" in cmdline
        is_native_runtime = str(NATIVE_GODOT_PATH) in cmdline and str(ROOT_DIR) in cmdline
        if not (is_project_runtime or is_native_runtime):
            continue
        pids.append(pid)
    return pids


def launch_command() -> list[str]:
    if NATIVE_GODOT_PATH.exists():
        return [str(NATIVE_GODOT_PATH), "--rendering-driver", "opengl3", "--path", str(ROOT_DIR)]
    return ["flatpak", "run", "org.godotengine.Godot", "--path", str(ROOT_DIR)]


def start_xvfb() -> None:
    global xvfb_proc, openbox_proc, X11_ENV, xvfb_log_handle
    if not USE_XVFB:
        return
    if xvfb_proc is not None and xvfb_proc.poll() is None:
        return
    xvfb_log_handle = (OUT_DIR / "xvfb.log").open("w", encoding="utf-8")
    display = XVFB_DISPLAY
    display_number = display.lstrip(":")
    subprocess.run(["pkill", "-f", f"Xvfb {display}"], check=False, capture_output=True, text=True)
    subprocess.run(["pkill", "-f", "openbox"], check=False, capture_output=True, text=True)
    time.sleep(0.5)
    proc = subprocess.Popen(
        [
            "Xvfb",
            display,
            "-screen",
            "0",
            "1920x1080x24",
            "-ac",
            "-nolisten",
            "tcp",
        ],
        stdout=xvfb_log_handle,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    xvfb_proc = proc
    X11_ENV = {
        **os.environ,
        "DISPLAY": display,
        "LIBGL_ALWAYS_SOFTWARE": "1",
        "UI_TEST_DISABLE_BEES": "1",
        "UI_TEST_CHEST_SCENARIO": "1",
        "UI_TEST_CHEST_SYNC_DIR": str(OUT_DIR),
        "UI_TEST_INSTANCE_ROLE": "client",
    }
    X11_ENV.pop("XAUTHORITY", None)
    for _ in range(30):
        if proc.poll() is not None:
            raise AssertionError("Xvfb exited before becoming ready")
        if Path(f"/tmp/.X11-unix/X{display_number}").exists():
            probe = subprocess.run(
                ["xwininfo", "-root"],
                env=X11_ENV,
                text=True,
                capture_output=True,
            )
            if probe.returncode != 0:
                time.sleep(0.1)
                continue
            openbox_proc = subprocess.Popen(
                ["openbox"],
                stdout=xvfb_log_handle,
                stderr=subprocess.STDOUT,
                text=True,
                start_new_session=True,
                env=X11_ENV,
            )
            time.sleep(1.0)
            phase("Xvfb prêt", f"display={display}")
            log(f"xvfb_display={display}")
            return
        time.sleep(0.1)
    raise AssertionError("Xvfb did not become ready")


def kill_stale_runtime_processes() -> None:
    if USE_XVFB:
        return
    pids = stale_runtime_pids()
    if not pids:
        return
    log(f"cleaning stale runtime processes={pids}")
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            continue
    time.sleep(1.0)
    for pid in pids:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            continue
    time.sleep(0.5)


def latest_runtime_window_id() -> str | None:
    runtime_ids = []
    for window_id, name in visible_godot_windows():
        if name == RUNTIME_NAME:
            runtime_ids.append(window_id)
    return runtime_ids[-1] if runtime_ids else None


def runtime_window_ids() -> list[str]:
    return [window_id for window_id, name in visible_godot_windows() if name == RUNTIME_NAME]

def wait_for_runtime_windows(expected_count: int, attempts: int = 120, delay: float = 0.25) -> list[str]:
    for _ in range(attempts):
        runtime_ids = runtime_window_ids()
        if len(runtime_ids) >= expected_count:
            return runtime_ids[-expected_count:]
        time.sleep(delay)
    return []


def activate_window(window_id: str) -> None:
    run_cmd(["xdotool", "windowactivate", "--sync", window_id])
    run_cmd(["xdotool", "windowraise", window_id])


def close_window(window_id: str) -> None:
    subprocess.run(["xdotool", "windowclose", window_id], env=X11_ENV, text=True, capture_output=True)


def window_geometry(window_id: str) -> dict[str, int]:
    output = xdotool("getwindowgeometry", "--shell", window_id)
    result: dict[str, int] = {}
    for line in output.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if value.isdigit():
            result[key] = int(value)
    return result


def display_geometry() -> tuple[int, int]:
    output = xdotool("getdisplaygeometry")
    width_text, height_text = output.split()
    return int(width_text), int(height_text)


def clamp_window_position(x: int, y: int, width: int, height: int) -> tuple[int, int]:
    screen_w, screen_h = display_geometry()
    clamped_x = max(0, min(x, max(0, screen_w - width)))
    clamped_y = max(0, min(y, max(0, screen_h - height)))
    return clamped_x, clamped_y


def place_window(window_id: str, x: int, y: int, width: int, height: int) -> None:
    x, y = clamp_window_position(x, y, width, height)
    activate_window(window_id)
    run_cmd(["xdotool", "windowsize", "--sync", window_id, str(width), str(height)])
    time.sleep(0.2)
    run_cmd(["xdotool", "windowmove", "--sync", window_id, str(x), str(y)])
    time.sleep(0.2)


def log_window_geometry(label: str, window_id: str) -> None:
    geometry = window_geometry(window_id)
    log(
        "%s_geometry=id=%s x=%s y=%s w=%s h=%s"
        % (
            label,
            window_id,
            geometry.get("X", -1),
            geometry.get("Y", -1),
            geometry.get("WIDTH", -1),
            geometry.get("HEIGHT", -1),
        )
    )


def click_window(window_id: str, x: int, y: int) -> None:
    activate_window(window_id)
    time.sleep(0.1)
    run_cmd(["xdotool", "mousemove", "--window", window_id, str(x), str(y)])
    run_cmd(["xdotool", "click", "1"])


def click_window_sequence(window_id: str, points: list[tuple[int, int]], pause: float = 0.4) -> None:
    for x, y in points:
        click_window(window_id, x, y)
        time.sleep(pause)


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
    return (w // 2, int(h * 0.48)), (w // 2, int(h * 0.57))


def wait_for_menu(window_id: str, probe_name: str, attempts: int = 30, delay: float = 0.25) -> bool:
    probe_path = OUT_DIR / f"{probe_name}_probe.png"
    for attempt in range(attempts):
        import_window(window_id, probe_path)
        visible = menu_visible_in_window_capture(probe_path)
        log(f"{probe_name}_probe[{attempt}]={1 if visible else 0}")
        if visible:
            shutil.copy2(probe_path, OUT_DIR / f"{probe_name}_ready.png")
            return True
        time.sleep(delay)
    if probe_path.exists():
        shutil.copy2(probe_path, OUT_DIR / f"{probe_name}_timeout.png")
    return False


def click_detected_menu_button(window_id: str, probe_image: Path, role: str, output_prefix: str) -> None:
    server_center, client_center = detect_menu_button_centers(probe_image)
    target = server_center if role == "server" else client_center
    log(f"{output_prefix}_button_center={target}")
    click_window(window_id, *target)


def wait_for_menu_to_disappear(window_id: str, output_prefix: str, attempts: int = 20, delay: float = 0.25) -> bool:
    probe_path = OUT_DIR / f"{output_prefix}_after_click_probe.png"
    for attempt in range(attempts):
        import_window(window_id, probe_path)
        still_visible = menu_visible_in_window_capture(probe_path)
        log(f"{output_prefix}_menu_gone_probe[{attempt}]={0 if still_visible else 1}")
        if not still_visible:
            shutil.copy2(probe_path, OUT_DIR / f"{output_prefix}_after_click_ready.png")
            return True
        time.sleep(delay)
    if probe_path.exists():
        shutil.copy2(probe_path, OUT_DIR / f"{output_prefix}_after_click_timeout.png")
    return False


def cleanup() -> None:
    if phase_lines:
        write_summary()
    for window_id in launched_runtime_window_ids:
        log(f"cleaning up launched runtime window={window_id}")
        close_window(window_id)
    time.sleep(1.0)
    for proc in launched_runtime_procs:
        if proc.poll() is not None:
            continue
        log(f"cleaning up launched runtime pid={proc.pid}")
        try:
            proc.terminate()
        except ProcessLookupError:
            continue
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            log(f"runtime pid={proc.pid} did not exit after windowclose+terminate")
    for handle in launched_runtime_log_handles:
        handle.close()
    if USE_XVFB:
        log("cleaning up openbox/Xvfb via pkill")
        subprocess.run(["pkill", "-f", "openbox"], check=False, capture_output=True, text=True)
        subprocess.run(["pkill", "-f", f"Xvfb {XVFB_DISPLAY}"], check=False, capture_output=True, text=True)
    if xvfb_log_handle is not None:
        xvfb_log_handle.close()
    run_log.close()


atexit.register(cleanup)


def launch_runtime_instance(label: str, role: str) -> subprocess.Popen[str]:
    log(f"starting runtime instance={label}")
    log_path = OUT_DIR / f"godot_runtime_{label}.log"
    log_path.write_text("", encoding="utf-8")
    log_handle = log_path.open("w", encoding="utf-8")
    launched_runtime_log_handles.append(log_handle)
    cmd = launch_command()
    log(f"launch_cmd[{label}]={' '.join(cmd)}")
    log(
        "launch_env[%s]=DISPLAY=%s LIBGL_ALWAYS_SOFTWARE=%s UI_TEST_DISABLE_BEES=%s UI_TEST_CHEST_SCENARIO=%s UI_TEST_AUTO_ROLE=%s"
        % (
            label,
            X11_ENV.get("DISPLAY", ""),
            X11_ENV.get("LIBGL_ALWAYS_SOFTWARE", ""),
            X11_ENV.get("UI_TEST_DISABLE_BEES", ""),
            X11_ENV.get("UI_TEST_CHEST_SCENARIO", ""),
            "server" if role == "server" else "client",
        )
    )
    env = {
        **X11_ENV,
        "UI_TEST_INSTANCE_ROLE": role,
        "UI_TEST_AUTO_ROLE": "server" if role == "server" else "client",
    }
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
    return proc


def ensure_runtime_windows(expected_count: int = 2) -> list[str]:
    current = runtime_window_ids()
    if current:
        log(f"unexpected visible runtimes before launch={current}")
    runtime_ids = current[:]
    while len(runtime_ids) < expected_count:
        label = f"{len(launched_runtime_procs) + 1}"
        phase("Lancement Godot", f"instance={label}")
        role = "server" if len(launched_runtime_procs) == 0 else "client"
        launch_runtime_instance(label, role)
        runtime_ids = wait_for_runtime_windows(len(runtime_ids) + 1)
        if len(runtime_ids) < len(launched_runtime_procs):
            try:
                import_root(OUT_DIR / "00_runtime_not_found.png")
            except subprocess.CalledProcessError:
                pass
            raise AssertionError(f"runtime window for instance {label} did not appear")
    dump_visible_godot_windows()
    if len(runtime_ids) < expected_count:
        try:
            import_root(OUT_DIR / "00_runtime_not_found.png")
        except subprocess.CalledProcessError:
            pass
        raise AssertionError(f"expected {expected_count} runtime windows, got {len(runtime_ids)}")
    launched_runtime_window_ids[:] = runtime_ids
    return runtime_ids


def _chest_json_path(role: str) -> Path:
    return OUT_DIR / f"chest_{role}.json"


def _read_chest_contents(role: str) -> list | None:
    path = _chest_json_path(role)
    if not path.exists():
        return None
    try:
        with path.open(encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, list) else None
    except (json.JSONDecodeError, OSError):
        return None


def _wait_chest_file(role: str, timeout_sec: float = 2.0, poll_interval: float = 0.1) -> list | None:
    deadline = time.monotonic() + timeout_sec
    while time.monotonic() < deadline:
        contents = _read_chest_contents(role)
        if contents is not None:
            return contents
        time.sleep(poll_interval)
    return None


def _total_quantity(contents: list) -> int:
    total = 0
    for slot in contents:
        if isinstance(slot, dict):
            total += int(slot.get("quantity", 0))
    return total


def assert_chest_after_take() -> None:
    """Vérifie que le coffre a bien été mis à jour après la prise (contenu valide, au moins 1 objet restant)."""
    contents = _wait_chest_file("client")
    if contents is None:
        raise AssertionError(
            "Fichier coffre client non trouvé après prise (UI_TEST_CHEST_SYNC_DIR / inventaire coffre non écrit)."
        )
    total = _total_quantity(contents)
    if total < 1:
        raise AssertionError(
            f"Coffre vide ou invalide après prise : attendu au moins 1 objet restant, total quantité={total}."
        )
    log(f"assert_chest_after_take OK: coffre client a {total} objet(s) restant(s).")


def main() -> int:
    log_process_snapshot()
    start_xvfb()
    kill_stale_runtime_processes()

    editor_id = latest_window_id(EDITOR_SEARCH, EDITOR_NAME) or ""
    log(f"editor_id={editor_id}")
    dump_visible_godot_windows()

    server_window_id, client_window_id = ensure_runtime_windows(2)
    phase("Fenêtres runtime détectées", f"server={server_window_id} client={client_window_id}")
    log(f"server_window_id={server_window_id}")
    log(f"client_window_id={client_window_id}")

    screen_w, screen_h = display_geometry()
    margin_x = 24
    margin_y = 72
    gap = 24
    available_w = screen_w - (margin_x * 2) - gap
    win_w = min(760, max(620, available_w // 2))
    win_h = min(720, max(520, screen_h - margin_y - 140))
    server_x = margin_x
    client_x = screen_w - margin_x - win_w
    server_y = margin_y
    client_y = margin_y
    place_window(server_window_id, server_x, server_y, win_w, win_h)
    place_window(client_window_id, client_x, client_y, win_w, win_h)
    phase("Fenêtres positionnées", f"gauche={server_x},{server_y} droite={client_x},{client_y} taille={win_w}x{win_h}")
    log_window_geometry("server", server_window_id)
    log_window_geometry("client", client_window_id)

    phase("Capture initiale", "01_runtime_start.png")
    import_root(OUT_DIR / "01_runtime_start.png")

    if AUTO_ROLE_BOOT:
        phase("Démarrage auto réseau", "server/client contournent le menu via UI_TEST_AUTO_ROLE")
        time.sleep(2.2)
    else:
        phase("Attente menus", "détection visuelle des boutons Server et Client")
        if not wait_for_menu(server_window_id, "02_server_menu"):
            raise AssertionError("server menu was not detected in server window")
        if not wait_for_menu(client_window_id, "03_client_menu"):
            raise AssertionError("client menu was not detected in client window")
        phase("Sélection du serveur", "clic sur le bouton Server dans la fenêtre gauche")
        click_detected_menu_button(server_window_id, OUT_DIR / "02_server_menu_ready.png", "server", "02_server")
        if not wait_for_menu_to_disappear(server_window_id, "02_server"):
            raise AssertionError("server window stayed on menu after server click")
        phase("Sélection du client", "clic sur le bouton Client dans la fenêtre droite")
        click_detected_menu_button(client_window_id, OUT_DIR / "03_client_menu_ready.png", "client", "03_client")
        if not wait_for_menu_to_disappear(client_window_id, "03_client"):
            raise AssertionError("client window stayed on menu after client click")
    time.sleep(1.2)

    phase("Multijoueur démarré", "04_after_multiplayer_start.png")
    import_root(OUT_DIR / "04_after_multiplayer_start.png")

    phase("Préparation coffre", "attente du joueur client devant le coffre avec inventaire ouvert")
    time.sleep(1.2)
    import_root(OUT_DIR / "05_chest_inventory_ready.png")

    client_geometry = window_geometry(client_window_id)
    client_w = client_geometry["WIDTH"]
    client_h = client_geometry["HEIGHT"]
    external_panel_x = client_w - 344
    external_panel_y = client_h - 250
    external_slot_click = (external_panel_x + 160, external_panel_y + 108)
    external_take_click = (external_panel_x + 78, external_panel_y + 184)

    log(f"external_slot_click={external_slot_click}")
    log(f"external_take_click={external_take_click}")
    phase("Prise depuis le coffre", "clic premier slot du coffre puis bouton Prendre")
    click_window_sequence(client_window_id, [external_slot_click, external_take_click], pause=0.6)
    time.sleep(1.0)

    phase("Vérification transfert", "06_after_chest_take.png")
    import_root(OUT_DIR / "06_after_chest_take.png")

    phase("Assertion coffre après prise", "contenu coffre écrit par le client")
    assert_chest_after_take()

    write_summary()
    log(f"screenshots={OUT_DIR}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        log(f"error: {exc}")
        sys.exit(1)
