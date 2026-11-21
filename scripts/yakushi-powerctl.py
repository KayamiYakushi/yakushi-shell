#!/usr/bin/python3 -I
"""The CPU power mode: power saving, balanced or performance.

    yakushi-powerctl.py status          (you)  {"mode", "modes", "canSet", "helper"} as JSON
    yakushi-powerctl set <mode>         (root) change it now and keep it for the next boot
    yakushi-powerctl apply              (root) the saved mode, once at boot (yakushi-power.service)

<mode> is saver, balanced or performance. Settings -> System runs `status`
as you and `set` through pkexec; the package installs this file as the root
helper /usr/lib/yakushi-shell/yakushi-powerctl, and its polkit rule lets the
person at the computer (the active local session) use it without a password,
as power-profiles-daemon does. Nothing else is accepted: no paths, no other
words, only the three modes, written to the kernel's own files:

  - every cpufreq policy's governor, and its energy preference where the
    driver has one (amd-pstate-epp, intel_pstate):
        saver        powersave + power
        balanced     powersave + balance_performance
        performance  performance
    Without an energy preference (acpi-cpufreq): powersave / schedutil (or
    ondemand) / performance.
  - the firmware's platform profile, when there is one (laptops):
    low-power / balanced / performance.

The chosen mode is kept in /var/lib/yakushi-shell/power-mode (one word).
"""
from pathlib import Path
import json
import os
import shutil
import sys

MODES = ("saver", "balanced", "performance")
CPUFREQ = Path("/sys/devices/system/cpu/cpufreq")
PLATFORM = Path("/sys/firmware/acpi/platform_profile")
PLATFORM_CHOICES = Path("/sys/firmware/acpi/platform_profile_choices")
STATE = Path("/var/lib/yakushi-shell/power-mode")
HELPER = Path("/usr/lib/yakushi-shell/yakushi-powerctl")
POLICY = Path("/usr/share/polkit-1/actions/org.yakushi.shell.power.policy")

# what each mode asks for, best first; the first one the machine has is used
GOVERNOR_EPP = {"saver": "powersave", "balanced": "powersave", "performance": "performance"}
EPP = {"saver": ("power", "balance_power"), "balanced": ("balance_performance", "default")}
GOVERNOR_PLAIN = {
    "saver": ("powersave", "conservative"),
    "balanced": ("schedutil", "ondemand", "conservative"),
    "performance": ("performance",),
}
PLATFORM_PROFILE = {
    "saver": ("low-power", "quiet", "cool"),
    "balanced": ("balanced",),
    "performance": ("performance", "balanced-performance"),
}


def fail(message, code=1):
    print(message, file=sys.stderr)
    raise SystemExit(code)


def read(path):
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def policies():
    return sorted(p for p in CPUFREQ.glob("policy[0-9]*") if (p / "scaling_governor").is_file())


def has_epp(policy):
    return (policy / "energy_performance_preference").is_file()


def first(wanted, available):
    return next((w for w in wanted if w in available), None)


def governor_for(policy, mode):
    governors = read(policy / "scaling_available_governors").split()
    if has_epp(policy):
        return GOVERNOR_EPP[mode] if GOVERNOR_EPP[mode] in governors else None
    return first(GOVERNOR_PLAIN[mode], governors)


def pref_for(policy, mode):
    """the energy preference for mode, or None (no such knob, or performance)"""
    if mode == "performance" or not has_epp(policy):
        return None
    # under the performance governor the driver offers only "performance":
    # ask again once the governor has changed; if it still does, use the
    # kernel's names (every EPP driver has them)
    prefs = read(policy / "energy_performance_available_preferences").split()
    return first(EPP[mode], prefs) or EPP[mode][0]


def modes():
    """the modes this machine can tell apart (two that come out the same are one)"""
    pols = policies()
    if not pols:
        return []
    seen, out = set(), []
    for mode in MODES:
        governor = governor_for(pols[0], mode)
        what = (governor, EPP.get(mode, ("",))[0] if has_epp(pols[0]) else "")
        if governor is not None and what not in seen:
            seen.add(what)
            out.append(mode)
    return out


def current():
    pols = policies()
    if not pols:
        return ""
    pol = pols[0]
    governor = read(pol / "scaling_governor")
    if governor == "performance":
        return "performance"
    if has_epp(pol):
        return "saver" if read(pol / "energy_performance_preference") in EPP["saver"] else "balanced"
    return "saver" if governor in GOVERNOR_PLAIN["saver"] else "balanced"


def status():
    can = HELPER.is_file() and POLICY.is_file() and shutil.which("pkexec") is not None
    print(json.dumps({"mode": current(), "modes": modes(), "canSet": can, "helper": str(HELPER)}))


def write_sys(path, value):
    try:
        path.write_text(value)
        return True
    except OSError as e:
        print(f"{path}: {e.strerror}", file=sys.stderr)
        return False


def apply(mode):
    pols = policies()
    if not pols:
        fail("This computer does not let the CPU speed be changed.")
    ok = True
    for pol in pols:
        governor = governor_for(pol, mode)
        if governor is None:
            ok = False
            continue
        # the governor first: with performance the driver holds the
        # energy preference and refuses a new one
        if read(pol / "scaling_governor") != governor:
            ok = write_sys(pol / "scaling_governor", governor) and ok
        pref = pref_for(pol, mode)
        if pref is not None and read(pol / "energy_performance_preference") != pref:
            ok = write_sys(pol / "energy_performance_preference", pref) and ok
    if PLATFORM.is_file():
        profile = first(PLATFORM_PROFILE[mode], read(PLATFORM_CHOICES).split())
        if profile is not None and read(PLATFORM) != profile:
            ok = write_sys(PLATFORM, profile) and ok
    return ok


def save(mode):
    STATE.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    tmp = STATE.parent / f".{STATE.name}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW | os.O_CLOEXEC, 0o644)
    with os.fdopen(fd, "w") as out:
        out.write(mode + "\n")
        out.flush()
        os.fsync(out.fileno())
    os.replace(tmp, STATE)


def main(argv):
    if argv == ["status"]:
        return status()
    if os.geteuid() != 0:
        fail("Only status works without root; Settings changes the mode through pkexec.")
    if len(argv) == 2 and argv[0] == "set" and argv[1] in MODES:
        if argv[1] not in modes():
            fail(f"This computer has no separate {argv[1]} mode.")
        ok = apply(argv[1])
        save(argv[1])
        if not ok:
            fail("Some CPUs did not take the new mode.")
        return
    if argv == ["apply"]:
        mode = read(STATE)
        if mode not in MODES:
            fail(f"{STATE}: no saved mode.")
        if not apply(mode):
            fail("Some CPUs did not take the saved mode.")
        return
    fail(__doc__.strip().split("\n\n")[1], 2)


if __name__ == "__main__":
    main(sys.argv[1:])
