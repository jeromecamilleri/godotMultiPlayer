#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]
BASE_SCRIPT = ROOT_DIR / "test" / "UI" / "test_cube_mission_ui.py"


def main() -> int:
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/tmp/cube-mission-lock-ui")
    cmd = [sys.executable, str(BASE_SCRIPT), str(out_dir)]
    env = dict(**__import__("os").environ)
    env["UI_TEST_SCENARIO_OVERRIDE"] = "cube_mission_lock"
    completed = subprocess.run(cmd, cwd=str(ROOT_DIR), env=env)
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
