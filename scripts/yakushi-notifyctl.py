#!/usr/bin/env python3
"""Settings backend for notifications.

Commands:
    get                     Print the settings as JSON.
    set enabled on|off      Show notifications, or not at all.
    set timeout <2..30>     Seconds a pop-up stays (when the app asks for none).
    toggle                  Flip `enabled`.
    test                    Send a test notification (through the shell).

Off does not stop the notification server: apps are still answered at once
(so nothing ever waits on a missing daemon), the notification is simply
dropped and never shown.

Settings live in the "notifications" section of ~/.config/yakushi/config.json
(see yakushi_config.py). The shell watches that file, so a change applies at
once. Runs only when called: no daemon, no timers.
"""
from __future__ import annotations

import json
import subprocess
import sys

import yakushi_config as config

DEFAULTS = {"enabled": True, "timeout": 5}
TIMEOUT_MIN, TIMEOUT_MAX = 2, 30


def emit(obj: dict) -> None:
    print(json.dumps(obj), flush=True)


def fail(message: str) -> None:
    emit({"ok": False, "message": message})
    raise SystemExit(1)


def sanitize(saved: dict) -> dict:
    state = dict(DEFAULTS)
    if isinstance(saved.get("enabled"), bool):
        state["enabled"] = saved["enabled"]
    timeout = saved.get("timeout")
    if isinstance(timeout, int) and not isinstance(timeout, bool):
        state["timeout"] = max(TIMEOUT_MIN, min(TIMEOUT_MAX, timeout))
    return state


def on_off(raw: str) -> bool:
    if raw in ("on", "true", "1"):
        return True
    if raw in ("off", "false", "0"):
        return False
    fail("Use on or off.")
    return False


def save(change) -> dict:
    def apply(saved: dict) -> dict:
        state = sanitize(saved)
        change(state)
        return state

    try:
        return config.update("notifications", apply)
    except config.NewerConfig as error:
        fail(str(error))
        return {}


def main() -> None:
    args = sys.argv[1:]

    if args == ["get"]:
        emit({"ok": True, **sanitize(config.section("notifications"))})

    elif len(args) == 3 and args[:2] == ["set", "enabled"]:
        value = on_off(args[2])
        state = save(lambda s: s.update(enabled=value))
        emit({"ok": True, **state, "message": "Notifications " + ("on." if value else "off.")})

    elif len(args) == 3 and args[:2] == ["set", "timeout"]:
        try:
            value = max(TIMEOUT_MIN, min(TIMEOUT_MAX, int(args[2])))
        except ValueError:
            fail("Timeout must be a whole number of seconds.")
            return
        state = save(lambda s: s.update(timeout=value))
        emit({"ok": True, **state, "message": f"Pop-ups stay {value} s."})

    elif args == ["toggle"]:
        state = save(lambda s: s.update(enabled=not s["enabled"]))
        emit({"ok": True, **state, "message": "Notifications " + ("on." if state["enabled"] else "off.")})

    elif args == ["test"]:
        enabled = sanitize(config.section("notifications"))["enabled"]
        try:
            # never wait long, whoever answers
            subprocess.run(["notify-send", "--app-name=Yakushi", "--icon=preferences-system-notifications",
                            "Test notification", "This is how a notification looks."],
                           capture_output=True, timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            fail("Could not send it: is notify-send (libnotify) installed?")
        emit({"ok": True, "enabled": enabled,
              "message": "Sent." if enabled else "Sent, but notifications are off: nothing is shown."})

    else:
        fail("Usage: get | set enabled on|off | set timeout <2..30> | toggle | test")


if __name__ == "__main__":
    main()
