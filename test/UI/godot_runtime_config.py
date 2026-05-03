from __future__ import annotations

import os
from pathlib import Path


NATIVE_GODOT_PATH = Path(os.environ.get("GODOT_BIN", "/dataSSD/godot/bin/godot.linuxbsd.editor.x86_64"))
RENDERING_DRIVER = os.environ.get("GODOT_RENDERING_DRIVER", "vulkan")
