#!/usr/bin/env python3
from __future__ import annotations

import atexit
import json
import math
import os
import random
import shutil
import statistics
import subprocess
import sys
import time
from collections import deque
from pathlib import Path

from PIL import Image


ROOT_DIR = Path(__file__).resolve().parents[2]
OUT_DIR = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/tmp/replication-stress-ui")
COUNTS_ARG = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("UI_STRESS_COUNTS", "10")
PLAYER_COUNTS = [int(part) for part in COUNTS_ARG.split(",") if part.strip()]
OUT_DIR.mkdir(parents=True, exist_ok=True)
RUN_LOG_PATH = OUT_DIR / "run.log"
SUMMARY_PATH = OUT_DIR / "summary.txt"
NATIVE_GODOT_PATH = Path("/dataSSD/Godot_v4.6.1-stable_linux.x86_64")
XVFB_DISPLAY = ":99"
RUNTIME_NAME = "MutliplayerTemplate (DEBUG)"
RUNTIME_SEARCH = "MutliplayerTemplate"
DISPLAY_WIDTH = 3840
DISPLAY_HEIGHT = 2160

run_log = RUN_LOG_PATH.open("w", encoding="utf-8", buffering=1)
phase_lines: list[str] = []
xvfb_log_handle = None
X11_ENV = dict(os.environ)
launched_runtime_procs: list[subprocess.Popen[str]] = []


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


def cleanup() -> None:
    for proc in reversed(launched_runtime_procs):
        if proc.poll() is None:
            proc.terminate()
    time.sleep(0.5)
    for proc in reversed(launched_runtime_procs):
        if proc.poll() is None:
            proc.kill()
    subprocess.run(["pkill", "-f", "openbox"], check=False, capture_output=True, text=True)
    subprocess.run(["pkill", "-f", f"Xvfb {XVFB_DISPLAY}"], check=False, capture_output=True, text=True)
    if xvfb_log_handle is not None:
        xvfb_log_handle.close()
    run_log.close()


atexit.register(cleanup)
atexit.register(write_summary)


def search_windows(pattern: str) -> list[str]:
    output = try_run_cmd(["xdotool", "search", "--onlyvisible", "--name", pattern])
    return [line.strip() for line in output.splitlines() if line.strip()]


def runtime_window_ids() -> list[str]:
    window_ids: list[str] = []
    for window_id in search_windows(RUNTIME_SEARCH):
        if window_name(window_id) == RUNTIME_NAME:
            window_ids.append(window_id)
    return window_ids


def window_name(window_id: str) -> str:
    return try_run_cmd(["xdotool", "getwindowname", window_id])


def import_root(output_path: Path) -> None:
    run_cmd(["import", "-window", "root", str(output_path)])


def import_window(window_id: str, output_path: Path) -> None:
    run_cmd(["import", "-window", window_id, str(output_path)])


def activate_window(window_id: str) -> None:
    run_cmd(["xdotool", "windowactivate", "--sync", window_id])
    run_cmd(["xdotool", "windowraise", window_id])


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


def place_window(window_id: str, x: int, y: int, width: int, height: int) -> None:
    activate_window(window_id)
    run_cmd(["xdotool", "windowsize", "--sync", window_id, str(width), str(height)])
    time.sleep(0.1)
    run_cmd(["xdotool", "windowmove", "--sync", window_id, str(max(0, x)), str(max(0, y))])
    time.sleep(0.1)


def click_window(window_id: str, x: int, y: int) -> None:
    activate_window(window_id)
    time.sleep(0.1)
    run_cmd(["xdotool", "mousemove", "--window", window_id, str(x), str(y)])
    run_cmd(["xdotool", "click", "1"])


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
    if len(components) < 2:
        raise RuntimeError("menu buttons not detected")
    upper = components[0]
    lower = components[1]
    return ((upper[1] + upper[2]) // 2, (upper[3] + upper[4]) // 2), ((lower[1] + lower[2]) // 2, (lower[3] + lower[4]) // 2)


def wait_for_menu(window_id: str, probe_name: str, run_dir: Path, attempts: int = 40, delay: float = 0.25) -> Path:
    probe_path = run_dir / f"{probe_name}_probe.png"
    for attempt in range(attempts):
        import_window(window_id, probe_path)
        visible = menu_visible_in_window_capture(probe_path)
        log(f"{probe_name}_probe[{attempt}]={1 if visible else 0}")
        if visible:
            ready = run_dir / f"{probe_name}_ready.png"
            shutil.copy2(probe_path, ready)
            return ready
        time.sleep(delay)
    raise RuntimeError(f"menu not detected for {probe_name}")


def wait_for_menu_to_disappear(window_id: str, output_prefix: str, run_dir: Path, attempts: int = 30, delay: float = 0.25) -> None:
    probe_path = run_dir / f"{output_prefix}_after_click_probe.png"
    for attempt in range(attempts):
        import_window(window_id, probe_path)
        still_visible = menu_visible_in_window_capture(probe_path)
        log(f"{output_prefix}_menu_gone_probe[{attempt}]={0 if still_visible else 1}")
        if not still_visible:
            shutil.copy2(probe_path, run_dir / f"{output_prefix}_after_click_ready.png")
            return
        time.sleep(delay)
    raise RuntimeError(f"menu still visible for {output_prefix}")


def start_xvfb(run_dir: Path) -> None:
    global xvfb_log_handle, X11_ENV
    xvfb_log_handle = (run_dir / "xvfb.log").open("w", encoding="utf-8")
    subprocess.run(["pkill", "-f", f"Xvfb {XVFB_DISPLAY}"], check=False, capture_output=True, text=True)
    subprocess.run(["pkill", "-f", "openbox"], check=False, capture_output=True, text=True)
    time.sleep(0.3)
    subprocess.Popen(
        ["Xvfb", XVFB_DISPLAY, "-screen", "0", f"{DISPLAY_WIDTH}x{DISPLAY_HEIGHT}x24", "-ac", "-nolisten", "tcp"],
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
    }
    deadline = time.monotonic() + 6.0
    while time.monotonic() < deadline:
        if try_run_cmd(["xdotool", "getdisplaygeometry"], env=X11_ENV):
            break
        time.sleep(0.1)
    subprocess.Popen(["openbox"], env=X11_ENV, text=True, start_new_session=True)
    time.sleep(0.6)


def launch_runtime(role: str, run_dir: Path, test_port: str) -> subprocess.Popen[str]:
    log_handle = (run_dir / f"{role}.log").open("w", encoding="utf-8")
    env = {
        **X11_ENV,
        "UI_TEST_SCENARIO": "replication_stress",
        "UI_TEST_SYNC_DIR": str(run_dir),
        "UI_TEST_PORT": test_port,
        "UI_TEST_INSTANCE_ROLE": role,
        "UI_TEST_AUTO_ROLE": "server" if role == "server" else "client",
    }
    command = [str(NATIVE_GODOT_PATH), "--rendering-driver", "opengl3", "--path", str(ROOT_DIR)]
    proc = subprocess.Popen(
        command,
        env=env,
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    launched_runtime_procs.append(proc)
    return proc


def wait_for_runtime_count(expected_count: int, timeout_sec: float = 20.0) -> list[str]:
    deadline = time.monotonic() + timeout_sec
    while time.monotonic() < deadline:
        window_ids = runtime_window_ids()
        if len(window_ids) >= expected_count:
            return window_ids[:expected_count]
        time.sleep(0.2)
    raise RuntimeError(f"expected {expected_count} runtime windows, got {len(runtime_window_ids())}")


def place_windows_grid(window_ids: list[str]) -> None:
    cols = 4
    rows = math.ceil(len(window_ids) / cols)
    margin_x = 12
    margin_y = 12
    cell_width = (DISPLAY_WIDTH - ((cols + 1) * margin_x)) // cols
    cell_height = (DISPLAY_HEIGHT - ((rows + 1) * margin_y)) // rows
    for index, window_id in enumerate(window_ids):
        col = index % cols
        row = index // cols
        x = margin_x + col * (cell_width + margin_x)
        y = margin_y + row * (cell_height + margin_y)
        place_window(window_id, x, y, cell_width, cell_height)


def click_role_button(window_id: str, role: str, probe_path: Path) -> None:
    server_center, client_center = detect_menu_button_centers(probe_path)
    target = server_center if role == "server" else client_center
    log(f"{role}_button_center={target}")
    click_window(window_id, *target)


def select_menu_role(window_id: str, role: str, run_dir: Path) -> None:
    last_error: Exception | None = None
    for attempt in range(3):
        probe_path = wait_for_menu(window_id, role, run_dir)
        click_role_button(window_id, role, probe_path)
        try:
            wait_for_menu_to_disappear(window_id, role, run_dir)
            return
        except RuntimeError as exc:
            last_error = exc
            log(f"{role}_retry[{attempt}]")
            time.sleep(0.6)
    if last_error is not None:
        raise last_error
    raise RuntimeError(f"unable to select menu role for {role}")


def read_json(path: Path) -> dict | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None


def wait_for_result_files(run_dir: Path, player_count: int, timeout_sec: float = 35.0) -> dict[str, dict]:
    expected_roles = [f"client_{i}" for i in range(1, player_count + 1)]
    deadline = time.monotonic() + timeout_sec
    results: dict[str, dict] = {}
    while time.monotonic() < deadline:
        for role in expected_roles:
            path = run_dir / f"replication_stress_{role}.json"
            data = read_json(path)
            if data is not None:
                results[role] = data
        server_data = read_json(run_dir / "replication_stress_server.json")
        if server_data is not None:
            results["server"] = server_data
        if all(role in results for role in expected_roles):
            return results
        time.sleep(0.25)
    missing = sorted(set(expected_roles) - set(results.keys()))
    raise RuntimeError(f"missing stress result files: {missing}")


def percentile(values: list[float], value: float) -> float:
    if not values:
        return -1.0
    values = sorted(values)
    if len(values) == 1:
        return values[0]
    position = (len(values) - 1) * value
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return values[lower]
    weight = position - lower
    return values[lower] * (1.0 - weight) + values[upper] * weight


def summarize_metrics(results: dict[str, dict]) -> dict[str, float | str]:
    client_roles = sorted(role for role in results if role.startswith("client_"))
    client_results = [results[role] for role in client_roles]
    avg_rtts = [float(item.get("network_rtt_avg_ms", -1.0)) for item in client_results if float(item.get("network_rtt_avg_ms", -1.0)) >= 0.0]
    last_rtts = [float(item.get("network_rtt_ms", -1.0)) for item in client_results if float(item.get("network_rtt_ms", -1.0)) >= 0.0]
    jitter = [float(item.get("network_jitter_ms", -1.0)) for item in client_results if float(item.get("network_jitter_ms", -1.0)) >= 0.0]
    door_delays = [float(item.get("door_replication_delay_ms", -1)) for item in client_results if float(item.get("door_replication_delay_ms", -1)) >= 0]
    wood_delays = [float(item.get("wood_replication_delay_ms", -1)) for item in client_results if float(item.get("wood_replication_delay_ms", -1)) >= 0]
    apple_delays = [float(item.get("apple_replication_delay_ms", -1)) for item in client_results if float(item.get("apple_replication_delay_ms", -1)) >= 0]
    chest_delays = [float(item.get("chest_replication_delay_ms", -1)) for item in client_results if float(item.get("chest_replication_delay_ms", -1)) >= 0]
    event_names = ["door_open_seen", "wood_hidden_seen", "apple_hidden_seen", "chest_wood_seen", "chest_apple_seen"]
    fanout: dict[str, float] = {}
    for event_name in event_names:
        observed = []
        for item in client_results:
            events = item.get("events_ms", {})
            if isinstance(events, dict) and event_name in events:
                observed.append(float(events[event_name]))
        fanout[event_name] = max(observed) - min(observed) if len(observed) >= 2 else -1.0
    max_event_ms = 0.0
    for item in client_results:
        events = item.get("events_ms", {})
        if isinstance(events, dict):
            for event_ms in events.values():
                max_event_ms = max(max_event_ms, float(event_ms))
    positive_fanout = [value for value in fanout.values() if value >= 0.0]
    max_fanout = max(positive_fanout) if positive_fanout else 0.0
    max_door_delay = max(door_delays) if door_delays else 0.0
    max_chest_delay = max(chest_delays) if chest_delays else 0.0
    health = "OK"
    if max_chest_delay > 1000.0 or max_door_delay > 800.0 or max_fanout > 1500.0 or max_event_ms > 8000.0:
        health = "DEGRADED"
    if max_chest_delay > 5000.0 or max_door_delay > 3000.0 or max_fanout > 6000.0 or max_event_ms > 12000.0:
        health = "UNSTABLE"
    return {
        "health": health,
        "rtt_avg_p50_ms": round(percentile(avg_rtts, 0.50), 1) if avg_rtts else -1.0,
        "rtt_avg_p95_ms": round(percentile(avg_rtts, 0.95), 1) if avg_rtts else -1.0,
        "rtt_last_max_ms": round(max(last_rtts), 1) if last_rtts else -1.0,
        "jitter_p95_ms": round(percentile(jitter, 0.95), 1) if jitter else -1.0,
        "door_replication_max_ms": round(max(door_delays), 1) if door_delays else -1.0,
        "wood_replication_max_ms": round(max(wood_delays), 1) if wood_delays else -1.0,
        "apple_replication_max_ms": round(max(apple_delays), 1) if apple_delays else -1.0,
        "chest_replication_max_ms": round(max(chest_delays), 1) if chest_delays else -1.0,
        "door_fanout_ms": round(fanout["door_open_seen"], 1),
        "wood_fanout_ms": round(fanout["wood_hidden_seen"], 1),
        "apple_fanout_ms": round(fanout["apple_hidden_seen"], 1),
        "chest_wood_fanout_ms": round(fanout["chest_wood_seen"], 1),
        "chest_apple_fanout_ms": round(fanout["chest_apple_seen"], 1),
        "scenario_complete_ms": round(max_event_ms, 1),
    }


def run_single_count(player_count: int) -> dict[str, float | str]:
    run_dir = OUT_DIR / f"players_{player_count}"
    run_dir.mkdir(parents=True, exist_ok=True)
    for old_file in run_dir.iterdir():
        if old_file.is_file():
            old_file.unlink()
    phase("Charge", f"{player_count} joueurs")
    test_port = str(25000 + (os.getpid() % 10000) + random.randint(0, 999))
    start_xvfb(run_dir)
    phase("Xvfb prêt", f"display={XVFB_DISPLAY} port={test_port}")
    total_instances = player_count + 1
    roles = ["server"] + [f"client_{i}" for i in range(1, player_count + 1)]
    for role in roles:
        phase("Lancement instance", role)
        launch_runtime(role, run_dir, test_port)
        time.sleep(0.2)
    window_ids = wait_for_runtime_count(total_instances)
    place_windows_grid(window_ids)
    import_root(run_dir / "01_grid_before_roles.png")
    phase("Fenêtres détectées", f"{len(window_ids)} runtime(s)")
    time.sleep(5.0)
    import_root(run_dir / "02_grid_after_roles.png")
    phase("Connexion auto validée", "rôles server/client injectés par env")
    results = wait_for_result_files(run_dir, player_count)
    import_root(run_dir / "03_grid_stress_done.png")
    sample_indexes = [1, max(1, player_count // 2), player_count]
    for sample_index in sample_indexes:
        role = f"client_{sample_index}"
        if role not in roles:
            continue
        window_id = window_ids[roles.index(role)]
        import_window(window_id, run_dir / f"{role}.png")
    metrics = summarize_metrics(results)
    phase(
        "Métriques",
        "health=%s rtt_p95=%sms chest_max=%sms scenario=%sms"
        % (
            metrics["health"],
            metrics["rtt_avg_p95_ms"],
            metrics["chest_replication_max_ms"],
            metrics["scenario_complete_ms"],
        ),
    )
    summary_lines = [
        f"player_count={player_count}",
        f"health={metrics['health']}",
        f"rtt_avg_p50_ms={metrics['rtt_avg_p50_ms']}",
        f"rtt_avg_p95_ms={metrics['rtt_avg_p95_ms']}",
        f"rtt_last_max_ms={metrics['rtt_last_max_ms']}",
        f"jitter_p95_ms={metrics['jitter_p95_ms']}",
        f"door_replication_max_ms={metrics['door_replication_max_ms']}",
        f"wood_replication_max_ms={metrics['wood_replication_max_ms']}",
        f"apple_replication_max_ms={metrics['apple_replication_max_ms']}",
        f"chest_replication_max_ms={metrics['chest_replication_max_ms']}",
        f"door_fanout_ms={metrics['door_fanout_ms']}",
        f"wood_fanout_ms={metrics['wood_fanout_ms']}",
        f"apple_fanout_ms={metrics['apple_fanout_ms']}",
        f"chest_wood_fanout_ms={metrics['chest_wood_fanout_ms']}",
        f"chest_apple_fanout_ms={metrics['chest_apple_fanout_ms']}",
        f"scenario_complete_ms={metrics['scenario_complete_ms']}",
    ]
    (run_dir / "summary.txt").write_text("\n".join(summary_lines) + "\n", encoding="utf-8")
    log(f"summary[{player_count}] -> {run_dir / 'summary.txt'}")
    for proc in reversed(launched_runtime_procs):
        if proc.poll() is None:
            proc.terminate()
    launched_runtime_procs.clear()
    subprocess.run(["pkill", "-f", "openbox"], check=False, capture_output=True, text=True)
    subprocess.run(["pkill", "-f", f"Xvfb {XVFB_DISPLAY}"], check=False, capture_output=True, text=True)
    time.sleep(0.5)
    return metrics


def main() -> int:
    results_by_count: dict[int, dict[str, float | str]] = {}
    for player_count in PLAYER_COUNTS:
        metrics = run_single_count(player_count)
        results_by_count[player_count] = metrics
    overall_lines = []
    unstable_from = None
    for player_count in PLAYER_COUNTS:
        metrics = results_by_count[player_count]
        overall_lines.append(
            "%d joueurs | %s | RTT p95=%sms | coffre max=%sms | scenario=%sms"
            % (
                player_count,
                metrics["health"],
                metrics["rtt_avg_p95_ms"],
                metrics["chest_replication_max_ms"],
                metrics["scenario_complete_ms"],
            )
        )
        if unstable_from is None and metrics["health"] != "OK":
            unstable_from = player_count
    if unstable_from is None:
        overall_lines.append("premier_palier_degradation=aucun sur cette campagne")
    else:
        overall_lines.append(f"premier_palier_degradation={unstable_from} joueurs")
    SUMMARY_PATH.write_text("\n".join(overall_lines) + "\n", encoding="utf-8")
    for line in overall_lines:
        log(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
