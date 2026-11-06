#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

HOME = Path.home()
STATE = HOME / ".config" / "quickshell" / "yakushi-panel-opacity.local.json"
THEME = HOME / ".config" / "quickshell" / "Theme.qml"

def emit(ok=True, **kwargs):
    payload = {"ok": ok}
    payload.update(kwargs)
    print(json.dumps(payload, ensure_ascii=False))

def fallback():
    try:
        text = THEME.read_text()
        match = re.search(r"property\s+real\s+panelOpacity\s*:\s*([0-9.]+)", text)
        if match:
            return max(0.40, min(1.0, float(match.group(1))))
    except Exception:
        pass
    return 0.80

def read_value():
    if STATE.exists():
        try:
            data = json.loads(STATE.read_text())
            return max(0.40, min(1.0, float(data["opacity"])))
        except Exception:
            pass
    return fallback()

def write_value(value):
    value = max(0.40, min(1.0, float(value)))
    STATE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE.with_suffix(STATE.suffix + ".tmp")
    tmp.write_text(json.dumps({"opacity": value}, indent=2) + "\n")
    tmp.replace(STATE)
    return value

def main():
    if len(sys.argv) < 2:
        emit(False, message="Usage: get | set <0.40..1.0>")
        raise SystemExit(2)

    if sys.argv[1] == "get":
        value = read_value()
        emit(True, opacity=value, percent=round(value * 100))
        return

    if sys.argv[1] == "set" and len(sys.argv) == 3:
        try:
            value = write_value(sys.argv[2])
        except ValueError:
            emit(False, message="Invalid opacity value.")
            raise SystemExit(1)

        emit(
            True,
            opacity=value,
            percent=round(value * 100),
            message=f"Panel opacity → {round(value * 100)}%",
        )
        return

    emit(False, message="Invalid command.")
    raise SystemExit(2)

if __name__ == "__main__":
    main()
