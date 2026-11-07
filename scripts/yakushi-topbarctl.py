#!/usr/bin/env python3
"""Settings backend for the Yakushi top bar.

Commands:
    get                     Print the bar settings as JSON.
    set <key> <value>       Change one setting.
                              seconds      on | off
                              clock24      on | off
                              opacity      0.40 .. 1.00
                              visualizer   hover | always | off
                              order        comma-separated module ids
                              module.<id>  on | off
    sensors                 Print the CPU/GPU temperature files as JSON.
    init                    Create the config file if it is missing.

Settings live in the "topbar" section of ~/.config/yakushi/config.json
(see yakushi_config.py). The shell watches that file with inotify and is
pinged over IPC after a save, so changes apply instantly without polling.
Runs only when called: no daemon, no timers.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import yakushi_config as config


MODULES = (
    "workspaces",
    "ram",
    "cpu",
    "cpuTemp",
    "gpuTemp",
    "media",
    "volume",
    "date",
    "time",
    "power",
)

# Default left-to-right order on the island
DEFAULT_ORDER = [
    "workspaces",
    "ram",
    "cpu",
    "cpuTemp",
    "gpuTemp",
    "date",
    "time",
    "media",
    "volume",
    "power",
]

VISUALIZER_MODES = ("hover", "always", "off")

DEFAULTS: dict = {
    "seconds": True,
    "clock24": True,
    "opacity": 0.90,
    "visualizer": "hover",
    "order": DEFAULT_ORDER,
    "modules": {name: True for name in MODULES},
}

OPACITY_MIN = 0.40
OPACITY_MAX = 1.00

# Preferred temperature sensors, best first
HWMON_ROOT = Path("/sys/class/hwmon")
CPU_DRIVERS = ("k10temp", "zenpower", "coretemp", "cpu_thermal")
CPU_LABEL_PRIORITY = ("Tctl", "Package id 0", "Tdie", "CPU")
GPU_DRIVERS = ("amdgpu", "radeon", "nouveau", "i915", "xe")
GPU_LABEL_PRIORITY = ("edge", "junction", "mem")


def emit(obj: dict) -> None:
    print(json.dumps(obj), flush=True)


def fail(message: str) -> None:
    emit({"ok": False, "message": message})
    raise SystemExit(1)


def clamp(value: float) -> float:
    return max(OPACITY_MIN, min(OPACITY_MAX, value))


def on_off(raw: str) -> bool:
    if raw in ("on", "true", "1"):
        return True
    if raw in ("off", "false", "0"):
        return False
    fail("Expected on or off.")
    return False


# ---------------------------------------------------------------------------
# State file
# ---------------------------------------------------------------------------

def clean_order(items) -> list[str]:
    """Known ids once each, in the given order; missing ones appended."""
    order: list[str] = []
    for item in items:
        if item in MODULES and item not in order:
            order.append(item)
    for item in DEFAULT_ORDER:
        if item not in order:
            order.append(item)
    return order


def sanitize(saved: dict) -> dict:
    """The saved section, with defaults filled in and bad values dropped."""
    state = json.loads(json.dumps(DEFAULTS))

    for key in ("seconds", "clock24"):
        if isinstance(saved.get(key), bool):
            state[key] = saved[key]

    opacity = saved.get("opacity")
    if isinstance(opacity, (int, float)) and not isinstance(opacity, bool):
        state["opacity"] = clamp(float(opacity))

    if saved.get("visualizer") in VISUALIZER_MODES:
        state["visualizer"] = saved["visualizer"]

    if isinstance(saved.get("order"), list):
        state["order"] = clean_order(saved["order"])

    modules = saved.get("modules")
    if isinstance(modules, dict):
        for name in MODULES:
            if isinstance(modules.get(name), bool):
                state["modules"][name] = modules[name]

    return state


def load() -> dict:
    return sanitize(config.section("topbar"))


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def get() -> None:
    emit({"ok": True, **load()})


def set_value(key: str, raw: str) -> None:
    message = ""

    def change(saved: dict) -> dict:
        nonlocal message
        state = sanitize(saved)

        if key == "seconds":
            state["seconds"] = on_off(raw)
            message = "Seconds " + ("on." if state["seconds"] else "off.")

        elif key == "clock24":
            state["clock24"] = on_off(raw)
            message = ("24-hour" if state["clock24"] else "12-hour") + " clock."

        elif key == "opacity":
            try:
                value = clamp(float(raw))
            except ValueError:
                fail("Invalid opacity.")
                return
            state["opacity"] = round(value, 3)
            message = f"Top bar opacity {round(value * 100)}%."

        elif key == "visualizer":
            if raw not in VISUALIZER_MODES:
                fail("Visualizer must be hover, always or off.")
            state["visualizer"] = raw

        elif key == "order":
            if raw == "default":
                state["order"] = list(DEFAULT_ORDER)
            else:
                state["order"] = clean_order(raw.split(","))

        elif key.startswith("module.") and key[7:] in MODULES:
            state["modules"][key[7:]] = on_off(raw)

        else:
            fail(f"Unknown setting: {key}")

        return state

    try:
        state = config.update("topbar", change)
    except config.NewerConfig as error:
        fail(str(error))
        return

    emit({"ok": True, **state, "message": message})


def read_text(path: Path) -> str:
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def find_sensor(drivers, label_priority) -> str | None:
    fallback = None

    for hwmon in sorted(HWMON_ROOT.glob("hwmon*")):
        if read_text(hwmon / "name") not in drivers:
            continue

        inputs = sorted(hwmon.glob("temp*_input"))
        if not inputs:
            continue

        labels = {
            path: read_text(hwmon / (path.name.removesuffix("_input") + "_label"))
            for path in inputs
        }

        for wanted in label_priority:
            for path, label in labels.items():
                if label == wanted:
                    return str(path)

        if fallback is None:
            fallback = str(inputs[0])

    return fallback


def sensors() -> None:
    emit({
        "ok": True,
        "cpu": find_sensor(CPU_DRIVERS, CPU_LABEL_PRIORITY),
        "gpu": find_sensor(GPU_DRIVERS, GPU_LABEL_PRIORITY),
    })


def main() -> None:
    args = sys.argv[1:]

    if args == ["get"]:
        get()
    elif len(args) == 3 and args[0] == "set":
        set_value(args[1], args[2])
    elif args == ["sensors"]:
        sensors()
    elif args == ["init"]:
        config.load()
        emit({"ok": True})
    else:
        fail("Usage: get | set <key> <value> | sensors | init")


if __name__ == "__main__":
    main()
