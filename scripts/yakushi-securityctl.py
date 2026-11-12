#!/usr/bin/env python3
"""Keeping this computer safe, without anything running in the background.
Used by Settings -> Security, and once at login.

    yakushi-securityctl.py status           the shield: firewall, what is reachable from
                                            outside, SSH, updates, auto lock, disk
                                            encryption, Secure Boot - and the guard's news
    yakushi-securityctl.py updates          look for updates and known security holes
                                            (checkupdates + arch-audit; needs the internet)
    yakushi-securityctl.py login            at login: the guard check and the update check
                                            (at most once a day); a Hyprland notification
                                            only when something is serious
    yakushi-securityctl.py guard            the guard check now
    yakushi-securityctl.py accept <key>|all "that was me": take changes into the baseline
    yakushi-securityctl.py firewall on|off  * ufw: block everything coming in, allow going out
    yakushi-securityctl.py ssh off          * stop and disable the SSH server
    yakushi-securityctl.py harden on|off    * kernel and network settings to their safe values
                                            (one file in /etc/sysctl.d, one for systemd-resolved,
                                            Avahi off, your home closed to other users); off
                                            puts everything back as it was
    yakushi-securityctl.py autolock <min>|off   lock after <min> idle minutes (the shell
                                            watches for idle itself; config "lock")
    yakushi-securityctl.py upgrade          * the system update (pacman -Syu), right in Settings:
                                            one JSON line per step, then {"done": ...}.
                                            pacman runs on its own: closing Settings never
                                            stops it halfway
    yakushi-securityctl.py follow           watch an update that is already running
    yakushi-securityctl.py scan             * compare every system file with its package
                                            (pacman -Qkk; a few minutes), and look for programs
                                            with root rights that no package installed

* needs your password: --password-stdin and the first line of stdin (Settings
  asks for it in the page; it goes to sudo through a pipe), else pkexec asks.

The guard keeps a fingerprint of the places an intruder changes to stay
(what starts at login, services and timers and their unit files, users and
the wheel group, SSH keys and config, shell start files and functions,
commands in ~/.local/bin, app launchers, PAM, the library loader, kernel
modules and boot options, udev rules, pacman hooks, pacman.conf, open
ports) and says what changed since you last accepted it, plus failed logins
and sudo use from the journal. A program you accepted once may open and
close its ports as it likes: only a program never seen before is news. State: ~/.local/state/yakushi/security.json (only you
can read it).
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

import yakushi_config as config
import yakushi_paths as paths

HERE = paths.SCRIPTS
HOME = paths.HOME
STATE = paths.STATE / "security.json"
OLD_IDLE_CONF = paths.STATE / "hypridle.conf"   # auto lock of earlier builds
AUTOLOCK_DEFAULT = 10               # minutes, when never set
DAY = 20 * 3600                     # "once a day", with some room

sys.dont_write_bytecode = True
_spec = importlib.util.spec_from_file_location("yakushi_taskctl", HERE / "yakushi-taskctl.py")
tasks = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tasks)


def emit(obj: dict) -> None:
    print(json.dumps(obj))


def run(cmd: list[str], timeout: int = 60, env: dict | None = None) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=env)
    except FileNotFoundError:
        return subprocess.CompletedProcess(cmd, 127, "", f"{cmd[0]} is not installed")
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(cmd, 124, "", f"{cmd[0]} took too long")


def have(tool: str) -> bool:
    return shutil.which(tool) is not None


def load() -> dict:
    try:
        data = json.loads(STATE.read_text())
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save(data: dict) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=1))
    os.chmod(tmp, 0o600)
    tmp.replace(STATE)


def read(path) -> str:
    return tasks.read(path)


def unit_state(unit: str) -> tuple[str, str]:
    a = run(["systemctl", "is-active", unit], 10).stdout.strip()
    e = run(["systemctl", "is-enabled", unit], 10).stdout.strip()
    return a, e


# ---- the shield -------------------------------------------------------------------------
def firewall() -> dict:
    ufw_on = re.search(r"^\s*ENABLED\s*=\s*yes", read("/etc/ufw/ufw.conf"), re.M | re.I) is not None
    ufw_active, _ = unit_state("ufw.service")
    if have("ufw") and ufw_on and ufw_active == "active":
        return {"on": True, "tool": "ufw", "text": "On (ufw): connections from outside are blocked unless you allowed them."}
    for unit, label in (("firewalld.service", "firewalld"), ("nftables.service", "nftables rules")):
        if unit_state(unit)[0] == "active":
            return {"on": True, "tool": label, "text": f"On ({label})."}
    if have("ufw"):
        return {"on": False, "tool": "ufw", "text": "Off: anything that listens can be reached from your network."}
    return {"on": False, "tool": "", "text": "No firewall is installed. TURN ON installs ufw (official repository)."}


LOCAL = re.compile(r"^(127\.|\[?::1\]?|localhost|\[?::ffff:127\.)")


# systemd puts every service and app in a cgroup of its own, and the kernel tells
# anyone which cgroup a socket belongs to - so we can name the owner of a port
# even when it runs as another user (ss -p only sees your own processes)
SERVICE_CG = re.compile(r"/system\.slice/(?:[^/]+\.slice/)*([^/]+?)(?:@[^/]*)?\.(?:service|socket)$")
USER_CG = re.compile(r"/user@\d+\.service/(.+)$")
FLATPAK_CG = re.compile(r"/app-flatpak-([A-Za-z0-9_.\-]+?)-\d+\.scope$")
APP_CG = re.compile(r"/app-(?:[^-/]+-)?([^/]+?)(?:@[^/]*)?(?:-[0-9a-f]{6,}|-\d+)?\.(?:scope|service)$")
UNIT_CG = re.compile(r"/([^/]+?)(?:@[^/]*)?\.service$")


def owner(cgroup: str, program: str, uid: str) -> tuple[str, str]:
    """(stable id, how to name it) of whoever holds a socket"""
    m = FLATPAK_CG.search(cgroup)
    if m:
        app = m.group(1)
        return "flatpak:" + app, f"{app.rsplit('.', 1)[-1]} (Flatpak app {app})"
    m = SERVICE_CG.search(cgroup)
    if m:
        return "service:" + m.group(1), f"{m.group(1)} (system service)"
    if USER_CG.search(cgroup):
        if program:
            return program, program
        m = APP_CG.search(cgroup)
        if m:
            return "app:" + m.group(1), f"{m.group(1)} (app)"
        m = UNIT_CG.search(cgroup)
        if m:
            return "user-service:" + m.group(1), f"{m.group(1)} (your service)"
    if program:
        return program, program
    if uid:
        try:
            import pwd
            name = pwd.getpwuid(int(uid)).pw_name
            return "", f"a program of the user {name}"
        except (KeyError, ValueError):
            pass
    return "", ""


def listening() -> list[dict]:
    """sockets open to the network (not only to this computer)"""
    res = run(["ss", "-tulnpeH", "--cgroup"], 10)
    if res.returncode != 0:                     # an ss without --cgroup
        res = run(["ss", "-tulnpeH"], 10)
    out = []
    for line in res.stdout.splitlines():
        p = line.split()
        if len(p) < 5:
            continue
        proto, local = p[0], p[4]
        addr, _, port = local.rpartition(":")
        addr = addr.split("%")[0]
        if LOCAL.match(addr):
            continue
        prog = re.search(r'users:\(\("([^"]+)",pid=(\d+)', line)
        cg = re.search(r"\bcgroup:(\S+)", line)
        uid = re.search(r"\buid:(\d+)", line)
        who, name = owner(cg.group(1) if cg else "", prog.group(1) if prog else "", uid.group(1) if uid else "")
        key = f"{proto}:{port}"
        if any(o["key"] == key and o["owner"] == who for o in out):
            continue
        out.append({"key": key, "proto": proto, "port": port, "address": addr or "*",
                    "owner": who, "program": name,
                    "oldKey": prog.group(1) if prog else "",      # how builds before 2026-11-08 named it
                    "pid": int(prog.group(2)) if prog else 0})
    return sorted(out, key=lambda o: (o["proto"], int(o["port"]) if o["port"].isdigit() else 0))


def ssh_server() -> dict:
    active, enabled = unit_state("sshd.service")
    return {"active": active == "active", "enabled": enabled == "enabled", "installed": have("sshd") or Path("/usr/bin/sshd").exists()}


def encrypted_root() -> dict:
    res = run(["lsblk", "-J", "-o", "NAME,TYPE,MOUNTPOINTS"], 10)
    try:
        tree = json.loads(res.stdout).get("blockdevices", [])
    except ValueError:
        return {"known": False, "on": False}

    def walk(nodes, chain):
        for n in nodes or []:
            here = chain + [n.get("type", "")]
            if "/" in (n.get("mountpoints") or []):
                return here
            found = walk(n.get("children"), here)
            if found:
                return found
        return None
    chain = walk(tree, [])
    if chain is None:
        return {"known": False, "on": False}
    return {"known": True, "on": "crypt" in chain}


def secure_boot() -> dict:
    if not Path("/sys/firmware/efi").exists():
        return {"known": True, "efi": False, "on": False}
    try:
        data = Path("/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c").read_bytes()
        return {"known": True, "efi": True, "on": data[-1] == 1}
    except OSError:
        return {"known": False, "efi": True, "on": False}


def autolock() -> dict:
    """the "lock" section of the config; the shell's idle watch reads the same"""
    value = config.section("lock").get("idleMinutes", AUTOLOCK_DEFAULT)
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        value = AUTOLOCK_DEFAULT
    minutes = "off" if value == 0 else str(min(value, 240))
    return {"minutes": minutes, "installed": True, "running": True}


# ---- hardening ---------------------------------------------------------------------------
# Settings that close doors nobody here uses. Each is safe for a desktop that
# plays games and runs Flatpak apps (nothing below touches user namespaces,
# ptrace between your own programs or performance).
SYSCTL_FILE = "/etc/sysctl.d/90-yakushi-hardening.conf"
RESOLVED_FILE = "/etc/systemd/resolved.conf.d/90-yakushi-hardening.conf"
AVAHI = ["avahi-daemon.socket", "avahi-daemon.service"]
HARDEN_SYSCTL = [
    # id, in words, [(kernel setting, safe value)]
    ("kexec", "Swapping the running kernel", [("kernel.kexec_load_disabled", "1")]),
    # 244 = sync, remount, end programs, restart (the emergency keys), no memory or debug dumps
    ("sysrq", "Debug keys (SysRq)", [("kernel.sysrq", "244")]),
    ("redirects", "Route changes sent by strangers", [
        ("net.ipv4.conf.all.accept_redirects", "0"), ("net.ipv4.conf.default.accept_redirects", "0"),
        ("net.ipv4.conf.all.secure_redirects", "0"), ("net.ipv4.conf.default.secure_redirects", "0"),
        ("net.ipv4.conf.all.send_redirects", "0"), ("net.ipv4.conf.default.send_redirects", "0"),
        ("net.ipv6.conf.all.accept_redirects", "0"), ("net.ipv6.conf.default.accept_redirects", "0")]),
    ("rfc1337", "Connections cut by forged packets", [("net.ipv4.tcp_rfc1337", "1")]),
    ("ldisc", "Line modules loaded by anyone", [("dev.tty.ldisc_autoload", "0")]),
    ("sticky", "Files planted in shared folders", [("fs.protected_fifos", "2"), ("fs.protected_regular", "2")]),
    ("ipv6", "IPv6 address that names this computer", [
        ("net.ipv6.conf.all.use_tempaddr", "2"), ("net.ipv6.conf.default.use_tempaddr", "2")]),
]
RESOLVED_LINES = ["[Resolve]", "LLMNR=no", "MulticastDNS=no", "DNSOverTLS=opportunistic"]


def sysctl_now(key: str) -> str:
    """the value, '' when it cannot be read"""
    return read("/proc/sys/" + key.replace(".", "/")).strip()


def sysctl_safe(key: str, want: str, now: str) -> bool:
    if key == "kernel.sysrq" and now.isdigit():      # anything inside the emergency keys
        return int(now) != 1 and int(now) & ~244 == 0
    return now == want


def resolved_now() -> dict | None:
    """how systemd-resolved stands; None when it is not what resolves names here"""
    res = run(["resolvectl", "status"], 10)
    m = re.search(r"^\s*Protocols:\s*(.+)$", res.stdout, re.M) if res.returncode == 0 else None   # the first is Global
    if not m:
        return None
    words = m.group(1).split()
    return {"llmnr": "-LLMNR" in words, "mdns": "-mDNS" in words,
            "dot": "+DNSOverTLS" in words or "DNSOverTLS=opportunistic" in words}


def avahi_on() -> bool:
    return "active" in run(["systemctl", "is-active", *AVAHI], 10).stdout.split()


def home_closed() -> bool:
    try:
        return HOME.stat().st_mode & 0o077 == 0
    except OSError:
        return True


def hardening() -> dict:
    items = []
    for ident, label, keys in HARDEN_SYSCTL:
        seen = [(k, want, sysctl_now(k)) for k, want in keys]
        seen = [x for x in seen if x[2]]             # a kernel without it: nothing to say
        if seen:
            items.append({"id": ident, "label": label, "ok": all(sysctl_safe(*x) for x in seen)})
    names = resolved_now()
    avahi = avahi_on()
    if names is not None:
        items.append({"id": "llmnr", "label": "Answering name calls (LLMNR)", "ok": names["llmnr"]})
    if names is not None or avahi:
        items.append({"id": "mdns", "label": "Announcing this computer (mDNS)",
                      "ok": not avahi and (names is None or names["mdns"])})
    if names is not None:
        items.append({"id": "dot", "label": "Name lookups anyone can read", "ok": names["dot"]})
    items.append({"id": "home", "label": "Home folder open to other users", "ok": home_closed()})
    return {"items": items, "total": len(items), "weak": sum(1 for i in items if not i["ok"]),
            "applied": Path(SYSCTL_FILE).exists() or Path(RESOLVED_FILE).exists()}


def shield_weak() -> list[dict]:
    """the protections that are off, for the guard's report (alert: act now)"""
    weak = []
    if not firewall()["on"]:
        weak.append({"id": "firewall", "alert": True, "text": "The firewall is off"})
    ssh = ssh_server()
    if ssh["active"]:
        weak.append({"id": "ssh", "alert": True, "text": "The SSH server is on"})
    if autolock()["minutes"] == "off":
        weak.append({"id": "autolock", "alert": False, "text": "Auto lock is off"})
    n = hardening()["weak"]
    if n:
        weak.append({"id": "hardening", "alert": False,
                     "text": f"{n} hardening setting{'s are' if n != 1 else ' is'} weaker than needed"})
    return weak


# ---- updates and known holes -------------------------------------------------------------
AUDIT = re.compile(r"^Package (\S+) is affected by (.+?)\.\s+(\w+) risk!(?:\s+Update to (\S+?)!)?", re.I)


def check_updates() -> dict:
    result = {"time": int(time.time()), "pending": [], "holes": [], "errors": []}
    if have("checkupdates"):
        # its copy of the package lists lives in ~/.cache, not in /tmp (which is
        # RAM): it stays small there, and the next check downloads only what changed
        db = paths.CACHE / "checkup-db"
        db.mkdir(parents=True, exist_ok=True)
        res = run(["checkupdates"], 180, env={**os.environ, "CHECKUPDATES_DB": str(db)})
        if res.returncode in (0, 2):            # 2 = no updates
            for line in res.stdout.splitlines():
                p = line.split()
                if len(p) >= 4 and p[2] == "->":
                    result["pending"].append({"name": p[0], "from": p[1], "to": p[3]})
        else:
            result["errors"].append("checkupdates could not reach the mirrors")
    else:
        result["errors"].append("pacman-contrib (checkupdates) is not installed")
    if have("arch-audit"):
        res = run(["arch-audit"], 120)
        if res.returncode == 0:
            for line in res.stdout.splitlines():
                m = AUDIT.match(line.strip())
                if m:
                    cves = [c.strip() for c in re.split(r",\s*|\s+and\s+", m.group(2)) if c.strip()]
                    result["holes"].append({"name": m.group(1), "issues": cves[:6], "count": len(cves),
                                            "risk": m.group(3).lower(), "fix": m.group(4) or ""})
        else:
            result["errors"].append("arch-audit could not reach security.archlinux.org")
    else:
        result["errors"].append("arch-audit is not installed")
    return result


# ---- the guard ------------------------------------------------------------------------------
def _home_form(path: Path) -> str:
    """~/... for paths in your home (how the guard has always named them)."""
    return "~/" + str(path.relative_to(HOME)) if path.is_relative_to(HOME) else str(path)


# what the guard watched before 2026-11-12 (a state file without "watching" has these)
FIRST_FILES = [
    _home_form(paths.CONFIG_HOME / "fish/config.fish"), "~/.bashrc", "~/.bash_profile", "~/.profile", "~/.zshrc", "~/.zprofile",
    "~/.xprofile", "~/.pam_environment", "~/.ssh/authorized_keys", "~/.ssh/rc",
    "/etc/ld.so.preload", "/etc/environment", "/etc/hosts", "/etc/pacman.conf", "/etc/shells",
]
FIRST_DIRS = [*(_home_form(paths.CONFIG_HOME / d) for d in ("fish/conf.d", "environment.d", "autostart", "systemd/user")),
              "/etc/xdg/autostart", "/etc/profile.d", "/etc/cron.d"]

WATCHED_FILES = FIRST_FILES + ["~/.ssh/config", "/etc/ld.so.conf", "/etc/nsswitch.conf", "/etc/crontab"]
WATCHED_DIRS = FIRST_DIRS                  # every file in the folder
# files written into the folder itself; a link counts by where it points (a
# link to a package's file would change with every update of that package)
WATCHED_PLAIN = [_home_form(paths.CONFIG_HOME / "fish/functions"), _home_form(paths.DATA_HOME / "applications"),
                 "/etc/pam.d", "/etc/ld.so.conf.d", "/etc/modules-load.d", "/etc/modprobe.d",
                 "/etc/udev/rules.d", "/etc/pacman.d/hooks"]
# unit files and their drop-in folders (links are what "enabled" already says)
WATCHED_UNITS = ["/etc/systemd/system", "/etc/systemd/user"]
# commands that come before the system's own: a new name is the news (your
# own tools update themselves there, so their content is not compared)
WATCHED_NAMES = ["~/.local/bin"]
OTHER_KEYS = ["kernel:cmdline"]
ROOTS = WATCHED_FILES + WATCHED_DIRS + WATCHED_PLAIN + WATCHED_UNITS + WATCHED_NAMES + OTHER_KEYS


def under(key: str, roots: list[str]) -> bool:
    """is this snapshot key one of these watched places, or inside one?"""
    return any(key == r or key == "file:" + r or key.startswith(f"file:{r}/") for r in roots)


def digest(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()[:16]
    except OSError:
        return ""


NAMES: dict[str, str] = {}          # port key -> who, for the messages of this run


def listed(folder: str) -> list[Path]:
    try:
        return sorted(Path(os.path.expanduser(folder)).iterdir())
    except OSError:
        return []


def snapshot() -> dict[str, str]:
    """key -> fingerprint of everything the guard watches"""
    snap: dict[str, str] = {}
    lua = read(paths.HYPR / "hyprland.lua")
    block = re.search(r"startup\s*=\s*\{(.*?)\n\}", lua, re.S)
    for line in (block.group(1) if block else "").splitlines():
        q = re.search(r'"([^"]+)"', line.split("--", 1)[0])
        if q:
            snap["startup:" + q.group(1)] = "1"
    for scope in ("system", "user"):
        cmd = ["systemctl"] + (["--user"] if scope == "user" else []) + [
            "list-unit-files", "--state=enabled", "--no-legend", "--plain"]
        for line in run(cmd, 20).stdout.splitlines():
            name = line.split()[0] if line.split() else ""
            if name:
                snap[f"unit:{scope}:{name}"] = "1"
    for line in read("/etc/passwd").splitlines():
        p = line.split(":")
        if len(p) >= 7 and (p[2] == "0" or not p[6].endswith(("nologin", "false", "/sync", "/shutdown", "/halt"))):
            snap["user:" + p[0]] = f"uid {p[2]}, {p[6]}"
    for line in read("/etc/group").splitlines():
        p = line.split(":")
        if len(p) >= 4 and p[0] in ("wheel", "sudo", "root"):
            snap["group:" + p[0]] = p[3]
    for f in WATCHED_FILES:
        path = Path(os.path.expanduser(f))
        if path.exists():
            snap["file:" + f] = digest(path)
    for d in WATCHED_DIRS:
        folder = Path(os.path.expanduser(d))
        try:
            for entry in sorted(folder.iterdir()):
                if entry.is_file():
                    snap["file:" + f"{d}/{entry.name}"] = digest(entry)
        except OSError:
            pass
    for d in WATCHED_PLAIN:
        for entry in listed(d):
            if entry.name.endswith(".cache"):       # rebuilt by the system (mimeinfo.cache)
                continue
            if entry.is_symlink():
                snap[f"file:{d}/{entry.name}"] = "-> " + os.readlink(entry)
            elif entry.is_file():
                snap[f"file:{d}/{entry.name}"] = digest(entry)
    for d in WATCHED_UNITS:
        for entry in listed(d):
            if entry.is_symlink():
                continue
            if entry.is_file():
                snap[f"file:{d}/{entry.name}"] = digest(entry)
            elif entry.is_dir() and entry.name.endswith(".d"):
                for inner in listed(f"{d}/{entry.name}"):
                    if inner.is_file() and not inner.is_symlink():
                        snap[f"file:{d}/{entry.name}/{inner.name}"] = digest(inner)
    for d in WATCHED_NAMES:
        for entry in listed(d):
            snap[f"file:{d}/{entry.name}"] = "1"
    cmdline = read("/proc/cmdline").strip()
    if cmdline:
        snap["kernel:cmdline"] = cmdline
    for sock in listening():
        # by owner when we can tell (apps pick new port numbers now and then),
        # else by port; the value says which ports, for the message only
        k = f"port:{sock['proto']}:{sock['owner']}" if sock["owner"] else "port:" + sock["key"]
        ports = set(snap.get(k, "").split(",")) - {""} | {sock["port"]}
        snap[k] = ",".join(sorted(ports, key=lambda x: int(x) if x.isdigit() else 0))
        if sock["program"]:
            NAMES[k] = sock["program"]
    return snap


def describe(key: str, kind: str, value: str = "") -> str:
    what, _, rest = key.partition(":")
    verb = {"new": "New", "gone": "Removed", "changed": "Changed"}[kind]
    if what == "startup":
        return f"{verb}: Hyprland starts at login: {rest}"
    if what == "unit":
        scope, _, name = rest.partition(":")
        return f"{verb}: {'your' if scope == 'user' else 'system'} service or timer enabled: {name}"
    if what == "user":
        return f"{verb}: user account that can log in: {rest}" + (f" ({value})" if value else "")
    if what == "group":
        return f"{verb}: members of the {rest} group (they can use sudo): {value or 'none'}"
    if what == "port":
        proto, _, which = rest.partition(":")
        ports = [x for x in value.split(",") if x.isdigit()] if value != "1" else []
        if which.isdigit():
            ports = ports or [which]
        who = NAMES.get(key) or ("" if which.isdigit() else which.split(":", 1)[-1])
        where = ("port " if len(ports) == 1 else "ports ") + ", ".join(ports) if ports else ""
        if kind == "gone":
            return f"{verb}: {who or 'something'} no longer listens to your network ({proto})" + (f": {where}" if where else "")
        return f"{verb}: {who or 'unknown program'} listens to your network ({proto})" + (f": {where}" if where else "")
    if what == "file":
        name = rest.rsplit("/", 1)[-1]
        if kind != "gone" and any(rest.startswith(d + "/") for d in WATCHED_NAMES) and shutil.which(name, path="/usr/bin"):
            return f"{verb}: {rest} (it runs instead of the system's own {name})"
        return f"{verb}: {rest}"
    if what == "kernel":
        return f"{verb}: the options the kernel starts with" + (f": {value[:120]}" if value and kind != "gone" else "")
    return f"{verb}: {key}"


def journal_since(since: int) -> dict:
    """failed logins, sudo use and SSH logins since a time"""
    out = {"readable": True, "failed": [], "sudo": [], "ssh": []}
    res = run(["journalctl", "--since", f"@{since}", "--no-pager", "-o", "json",
               "SYSLOG_IDENTIFIER=sudo", "+", "SYSLOG_IDENTIFIER=sshd", "+", "SYSLOG_IDENTIFIER=sshd-session",
               "+", "SYSLOG_IDENTIFIER=login", "+", "SYSLOG_IDENTIFIER=su",
               "+", "SYSLOG_IDENTIFIER=unix_chkpwd", "+", "SYSLOG_IDENTIFIER=polkit-agent-helper-1",
               "+", "SYSLOG_IDENTIFIER=hyprlock", "+", "SYSLOG_IDENTIFIER=sddm-helper",
               "+", "SYSLOG_IDENTIFIER=qs", "+", "SYSLOG_IDENTIFIER=quickshell"], 30)
    low = res.stderr.lower()
    if "insufficient permissions" in low or "not seeing messages" in low or (res.returncode != 0 and not res.stdout):
        out["readable"] = False
        return out
    for line in res.stdout.splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        msg = e.get("MESSAGE")
        if not isinstance(msg, str):
            continue
        when = int(int(e.get("__REALTIME_TIMESTAMP", "0")) / 1e6)
        who = e.get("SYSLOG_IDENTIFIER", "")
        if re.search(r"authentication failure|Failed password|incorrect password|Invalid user|FAILED LOGIN", msg, re.I):
            if any(f["time"] == when and f["by"] != who for f in out["failed"][-3:]):
                continue                    # the same try, logged twice (pam + helper)
            out["failed"].append({"time": when, "by": who, "remote": who.startswith("sshd"), "text": msg[:160]})
        elif who == "sudo" and "COMMAND=" in msg:
            out["sudo"].append({"time": when, "text": msg.split("COMMAND=", 1)[1][:160]})
        elif who.startswith("sshd") and msg.startswith("Accepted"):
            out["ssh"].append({"time": when, "text": msg[:160]})
    for k in ("failed", "sudo", "ssh"):
        out[k] = out[k][-50:]
    return out


def migrate_ports(data: dict, base: dict) -> None:
    """Older builds named a port by its number, or by the program when ss could see it.
    Rename what is still open to the owner's name; old numbers that are closed now
    are dropped (a closed port is no danger). Things not in the baseline stay new."""
    socks = listening()
    for sock in socks:
        old = f"port:{sock['proto']}:{sock['oldKey'] or sock['port']}"
        if old in base and sock["owner"]:
            base.pop(old)
            base[f"port:{sock['proto']}:{sock['owner']}"] = sock["port"]
    for k in [k for k in base if k.startswith("port:") and k.split(":", 2)[2].isdigit()]:
        if not any(f"port:{s['key']}" == k and not s["owner"] for s in socks):
            base.pop(k)
    data["baseline"] = base
    data["portKeys"] = 2


def guard(data: dict) -> dict:
    """compare with the baseline; the first run takes the baseline"""
    now = int(time.time())
    snap = snapshot()
    base = data.get("baseline")
    if not isinstance(base, dict):
        data["baseline"] = snap
        data["portKeys"] = 2
        data["watching"] = ROOTS
        data["shield"] = shield_weak()
        data["changes"] = []
        data["guardTime"] = now
        data["events"] = {"readable": True, "failed": [], "sudo": [], "ssh": [], "since": now}
        return {"first": True, "changes": []}
    if data.get("portKeys") != 2:
        migrate_ports(data, base)
    # places watched since this build: what is there now is where we start
    # (asking you about forty files nobody touched would teach you to click
    # them away)
    watching = data.get("watching")
    known = watching if isinstance(watching, list) else FIRST_FILES + FIRST_DIRS
    fresh = [r for r in ROOTS if r not in known]
    if fresh:
        for k, v in snap.items():
            if k not in base and under(k, fresh):
                base[k] = v
    data["watching"] = ROOTS
    changes = []
    for k, v in snap.items():
        if k not in base:
            changes.append({"key": k, "kind": "new", "text": describe(k, "new", v)})
        elif base[k] != v and not k.startswith("port:"):    # new port numbers of a known owner are fine
            changes.append({"key": k, "kind": "changed", "text": describe(k, "changed", v)})
    for k, v in list(base.items()):
        if k in snap:
            continue
        if k.startswith("port:"):
            # a closed port is no danger and no news. A program you know
            # stays known (it opens its ports again the next time it runs);
            # a bare port number says nothing about who comes back to it
            if k.split(":", 2)[2].isdigit():
                base.pop(k)
            continue
        changes.append({"key": k, "kind": "gone", "text": describe(k, "gone", v)})
    data["changes"] = changes
    data["current"] = snap
    data["shield"] = shield_weak()
    since = int(data.get("events", {}).get("since") or data.get("guardTime") or now - 86400)
    # read only what is new since the last check; older ones are kept below
    ev = journal_since(max(since, int(data.get("guardTime") or since) - 5))
    old = data.get("events", {})
    for k in ("failed", "sudo", "ssh"):            # keep what was not looked at yet
        seen = {(x["time"], x["text"]) for x in old.get(k, [])}
        ev[k] = old.get(k, []) + [x for x in ev[k] if (x["time"], x["text"]) not in seen]
        ev[k] = ev[k][-50:]
    ev["since"] = since
    data["events"] = ev
    data["guardTime"] = now
    return {"first": False, "changes": changes}


def accept(data: dict, which: str) -> None:
    snap = data.get("current") or snapshot()
    base = data.get("baseline") or {}
    keys = [c["key"] for c in data.get("changes", [])] if which == "all" else [which]
    for k in keys:
        if k in snap:
            base[k] = snap[k]
        else:
            base.pop(k, None)
    data["baseline"] = base
    data["changes"] = [c for c in data.get("changes", []) if c["key"] not in keys]


def clear_events(data: dict) -> None:
    data["events"] = {"readable": data.get("events", {}).get("readable", True),
                      "failed": [], "sudo": [], "ssh": [], "since": int(time.time())}


def notify(text: str) -> None:
    """Hyprland's own notification (no notification daemon needed)"""
    if have("hyprctl"):
        run(["hyprctl", "notify", "0", "12000", "rgb(e2202f)", "fontsize:14", text], 10)


# ---- doing things as root -------------------------------------------------------------------
def root(cmd: list[str], timeout: int = 600) -> dict:
    result, err = tasks.as_root(cmd, timeout)
    if result == "ok":
        return {"ok": True}
    return {"ok": False, "wrongPassword": result == "wrong",
            "message": tasks.ROOT_MESSAGES.get(result, err or "It did not work.")}


def set_firewall(on: bool) -> dict:
    if on:
        script = ("command -v ufw >/dev/null || pacman -S --needed --noconfirm ufw || exit 3; "
                  "ufw default deny incoming && ufw default allow outgoing && ufw --force enable "
                  "&& systemctl enable --now ufw.service")
    else:
        script = "ufw disable && systemctl disable --now ufw.service"
    r = root(["/bin/sh", "-c", script])
    if r["ok"]:
        r["message"] = ("Firewall on: nothing from outside can connect unless you allow it."
                        if on else "Firewall off.")
    return r


def ssh_off() -> dict:
    r = root(["systemctl", "disable", "--now", "sshd.service", "sshd.socket"])
    if not r["ok"] and not r.get("wrongPassword") and not ssh_server()["active"]:
        r = {"ok": True}
    if r["ok"]:
        r["message"] = "The SSH server is off and will not start at boot."
    return r


def set_hardening(on: bool) -> dict:
    import shlex
    data = load()
    mine = data.get("hardening") if isinstance(data.get("hardening"), dict) else {}
    keys = [k for _, _, pairs in HARDEN_SYSCTL for k in pairs]
    resolved = "if systemctl -q is-active systemd-resolved.service; then systemctl restart systemd-resolved.service; fi"
    if on:
        before = mine.get("before") if isinstance(mine.get("before"), dict) else {}
        for key, _ in keys:                     # how it was, for "off" (kept from the first time)
            now = sysctl_now(key)
            if now.isdigit():
                before.setdefault(key, now)
        mine["before"] = before
        if "avahi" not in mine:
            mine["avahi"] = avahi_on() or any(unit_state(u)[1] == "enabled" for u in AVAHI)
        if "homeMode" not in mine:
            mine["homeMode"] = HOME.stat().st_mode & 0o777
        # "-" in front: a kernel without that setting is not an error
        lines = ["# Written by Yakushi Shell (Settings -> Security -> Hardening).",
                 "# HARDEN writes it, UNDO removes it."] + [f"-{k} = {v}" for k, v in keys]
        text = " ".join(shlex.quote(l) for l in lines)
        names = " ".join(shlex.quote(l) for l in RESOLVED_LINES)
        script = ("set -e; umask 022; "
                  f"mkdir -p {os.path.dirname(SYSCTL_FILE)} {os.path.dirname(RESOLVED_FILE)}; "
                  f"printf '%s\\n' {text} > {SYSCTL_FILE}; "
                  f"printf '%s\\n' {names} > {RESOLVED_FILE}; "
                  f"sysctl -q -p {SYSCTL_FILE} || true; {resolved}; "
                  f"systemctl disable --now {' '.join(AVAHI)} >/dev/null 2>&1 || true")
    else:
        back = [f"{k}={mine['before'][k]}" for k, _ in keys
                if isinstance(mine.get("before"), dict) and re.fullmatch(r"\d+", str(mine["before"].get(k, "")))]
        script = (f"rm -f {SYSCTL_FILE} {RESOLVED_FILE}; "
                  + "".join(f"sysctl -q -w {shlex.quote(b)} 2>/dev/null || true; " for b in back)
                  + resolved
                  + (f"; systemctl enable --now {' '.join(AVAHI)} >/dev/null 2>&1 || true" if mine.get("avahi") else ""))
    r = root(["/bin/sh", "-c", script])
    if not r["ok"]:
        return r
    try:                                         # your own folder: no root needed
        if on:
            os.chmod(HOME, HOME.stat().st_mode & 0o700)
        elif isinstance(mine.get("homeMode"), int) and home_closed():
            os.chmod(HOME, mine["homeMode"] & 0o777)
    except OSError:
        pass
    data = load()
    if on:
        data["hardening"] = mine
    else:
        data.pop("hardening", None)
    base = data.get("baseline")
    if isinstance(base, dict):                   # Avahi on or off was this button, not news
        for unit in AVAHI:
            if unit_state(unit)[1] == "enabled":
                base[f"unit:system:{unit}"] = "1"
            else:
                base.pop(f"unit:system:{unit}", None)
        data["changes"] = [c for c in data.get("changes", []) if c.get("key") not in
                           [f"unit:system:{u}" for u in AVAHI]]
    data["shield"] = shield_weak()
    save(data)
    left = hardening()["weak"]
    if on:
        r["message"] = ("Hardened: every setting is at its safe value." if left == 0 else
                        f"Hardened, but {left} setting{'s' if left != 1 else ''} did not take. They are marked below.")
    else:
        r["message"] = "Hardening undone. The kernel settings are fully back after a restart."
    return r


def stop_old_idle() -> None:
    """earlier builds ran hypridle with their own config: end it, once"""
    if OLD_IDLE_CONF.exists():
        run(["pkill", "-u", str(os.getuid()), "-f", f"hypridle -c {OLD_IDLE_CONF}"], 5)   # only ours
        try:
            OLD_IDLE_CONF.unlink()
        except OSError:
            pass


def set_autolock(minutes: str) -> dict:
    if minutes != "off" and not (minutes.isdigit() and 1 <= int(minutes) <= 240):
        return {"ok": False, "message": "Minutes from 1 to 240, or off."}
    value = 0 if minutes == "off" else int(minutes)
    try:
        config.update("lock", lambda saved: saved.update(idleMinutes=value))
    except config.NewerConfig as error:
        return {"ok": False, "message": str(error)}
    stop_old_idle()
    return {"ok": True, "message": "Auto lock off." if value == 0
            else f"The screen locks after {value} idle minutes."}


# caches that pacman hooks rebuild after installs: they never match the
# package's copy, and that is how it should be
REBUILT = re.compile(r"(\.cache|/plugins\.dat|/locale-archive|/gschemas\.compiled|/mime/[^/]+|/info/dir|"
                     r"/ld\.so\.cache|/fonts\.(dir|scale)|/\.uuid)$")
SCAN_RED = re.compile(r"^warning:\s+(\S+):\s+(/.*?)\s+\(([^()]+)\)$")


# files that run with their owner's or group's rights (setuid, setgid), on every
# real disk and RAM disk that is mounted; -xdev keeps find out of snapshots
SUID_MARK = "@@yakushi-suid"
SUID_FIND = ("findmnt -rno TARGET -t btrfs,ext4,ext3,ext2,xfs,f2fs,bcachefs,zfs,tmpfs | while IFS= read -r m; do "
             "find \"$m\" -xdev -type f -perm /6000 2>/dev/null; done")
# Flatpak keeps its runtimes' files as they came; apps run with setuid switched off
SUID_FINE = re.compile(r"^(/var/lib/flatpak/|/home/[^/]+/\.local/share/flatpak/)")


def unowned(paths_: list[str]) -> list[str]:
    """the ones no package installed (asking pacman needs no root)"""
    out = []
    for path in sorted(set(paths_)):
        if SUID_FINE.match(path) or not path.startswith("/"):
            continue
        if run(["pacman", "-Qqo", "--", path], 20).returncode != 0:
            out.append(path)
    return out


def deep_scan() -> dict:
    out = tasks.PASSWORD
    cmd = ["/bin/sh", "-c", f"LC_ALL=C pacman -Qkk 2>&1; echo {SUID_MARK}; {SUID_FIND}; exit 0"]
    if out is not None:
        res = subprocess.run(["sudo", "-S", "-k", "-p", "", "--", *cmd], input=out + "\n",
                             capture_output=True, text=True, timeout=1800)
        if res.returncode != 0 and ("incorrect password" in res.stderr or "Sorry, try again" in res.stderr):
            return {"ok": False, "wrongPassword": True, "message": tasks.ROOT_MESSAGES["wrong"]}
    else:
        res = run(["pkexec", *cmd], 1800)
        if res.returncode in (126, 127):
            return {"ok": False, "message": tasks.ROOT_MESSAGES["cancel"]}
    red, configs, other, caches = {}, 0, 0, set()
    files, _, special = res.stdout.partition(SUID_MARK)
    suid = unowned(special.split("\n"))
    for line in files.splitlines():
        m = SCAN_RED.match(line.strip())
        if not m:
            continue
        pkg, path, why = m.groups()
        if path.startswith("/etc/") or "backup" in why.lower():
            configs += 1                    # your own settings: changes are normal
            continue
        if REBUILT.search(path):
            caches.add(path)                # rebuilt on this computer by a pacman hook
            continue
        serious = re.search(r"checksum|size mismatch|symlink", why, re.I) and \
            re.match(r"^/(usr/(bin|sbin|lib|lib64|local/bin)|boot|bin|sbin|lib)", path)
        if serious:
            if path in red:                 # one file, several reasons: one line
                red[path]["why"] += ", " + why
            else:
                red[path] = {"package": pkg, "path": path, "why": why}
        else:
            other += 1
    red = list(red.values())
    result = {"time": int(time.time()), "red": red[:100], "redCount": len(red), "configs": configs,
              "caches": len(caches), "other": other, "suid": suid[:50]}
    data = load()
    data["scan"] = result
    save(data)
    msg = ("No system program was changed: every one matches its package."
           if not red else f"{len(red)} system files differ from their package. Look at them below.")
    if suid:
        msg += f" {len(suid)} program{'s' if len(suid) != 1 else ''} with root rights came from no package."
    return {"ok": True, "message": msg, "scan": result}


# ---- the system update, inside Settings -----------------------------------------------------
# pacman runs detached (its own session, output into a file), so closing
# Settings or this helper can never stop it halfway. This helper only reads
# the file and tells the page how far it is.
UPDATE_LOG = STATE.parent / "update.log"
UPDATE_RUN = STATE.parent / "update.run"          # "<pid> <start>" while it runs
EXIT_MARK = "@@yakushi-exit "
PHASES = [
    (":: Synchronizing package databases", "Refreshing the package lists"),
    (":: Starting full system upgrade", "Looking for updates"),
    (":: Retrieving packages", "Downloading"),
    ("checking keyring", "Checking signatures"),
    ("checking package integrity", "Checking packages"),
    ("checking for file conflicts", "Checking packages"),
    (":: Processing package changes", "Installing"),
    (":: Running pre-transaction hooks", "Preparing"),
    (":: Running post-transaction hooks", "Finishing up"),
]


def update_pid() -> int:
    """the running update's pid, or 0"""
    try:
        pid, start = (int(x) for x in UPDATE_RUN.read_text().split()[:2])
    except (OSError, ValueError):
        return 0
    st = tasks.stat(pid)
    return pid if st is not None and st["start"] == start and st["state"] != "Z" else 0


def kernels() -> set[str]:
    out = set()
    for f in Path("/usr/lib/modules").glob("*/pkgbase"):
        name = read(f).strip()
        if name:
            out.add(name)
    return out or {"linux"}


def summary(text: str) -> dict:
    """what an update log says, in words"""
    lines = text.splitlines()
    m = [l for l in lines if l.startswith(EXIT_MARK)]
    code = int(m[-1][len(EXIT_MARK):].strip() or 1) if m else None
    if code is None and re.search(r"Sorry, try again|incorrect password|no password was provided|password is required", text):
        return {"ok": False, "wrongPassword": True, "message": tasks.ROOT_MESSAGES["wrong"]}
    upgraded = re.findall(r"^\(\s*\d+/\d+\) (?:upgrading|installing) (\S+)", text, re.M)
    pacnew = re.findall(r"installed as (\S+\.pacnew)", text)
    k = kernels()
    restart = any(u in k for u in upgraded)
    relog = not restart and any(u in ("hyprland", "systemd", "glibc", "mesa", "quickshell") for u in upgraded)
    if code == 0:
        if "there is nothing to do" in text:
            msg = "Everything was already up to date."
        else:
            msg = f"Updated {len(upgraded)} package{'s' if len(upgraded) != 1 else ''}."
            if restart:
                msg += " A new kernel is installed: restart the computer when you can."
            elif relog:
                msg += " Log out and back in when you can, so everything uses the new versions."
        if pacnew:
            msg += f" {len(pacnew)} settings file(s) got a new default next to yours (.pacnew); yours were kept."
        return {"ok": True, "message": msg, "restart": restart, "relog": relog, "pacnew": pacnew[:10]}
    errors = [l for l in lines if l.startswith("error:")]
    why = errors[-1][6:].strip() if errors else (lines[-2] if len(lines) > 1 else "")
    if code is None:
        why = why or "it stopped before finishing"
    msg = "The update did not finish: " + why
    if re.search(r"conflict|could not satisfy|breaks dependency|are in conflict", text):
        msg += ". pacman needs a decision from you: OPEN IN TERMINAL lets you answer it."
    elif "Could not resolve host" in text or "failed retrieving file" in text:
        msg += ". Check the internet connection and try again."
    return {"ok": False, "message": msg, "terminal": True}


def finish(data: dict) -> dict:
    """the update ended: remember its result"""
    result = summary(read(UPDATE_LOG))
    result["time"] = int(time.time())
    UPDATE_RUN.unlink(missing_ok=True)
    if not result.get("wrongPassword"):
        data["lastUpdate"] = result
    return result


class Progress:
    def __init__(self):
        self.phase, self.n, self.total, self.got = "Starting", 0, 0, 0

    def feed(self, line: str) -> dict | None:
        l = line.strip()
        if not l or l.startswith(EXIT_MARK):
            return None
        for head, phase in PHASES:
            if l.startswith(head):
                self.phase, self.n = phase, 0
                if phase == "Downloading":
                    self.got = 0            # the package lists before were not packages
        m = re.match(r"^Packages \((\d+)\)", l)
        if m:
            self.total = int(m.group(1))
        if l.endswith("downloading..."):
            self.phase = "Downloading"
            self.got += 1
            self.n = min(self.got, self.total) if self.total else self.got
        m = re.match(r"^\(\s*(\d+)/(\d+)\)", l)
        if m:
            self.n, self.total = int(m.group(1)), int(m.group(2))
            if self.phase == "Downloading":
                self.phase = "Installing"
        if l.startswith("there is nothing to do"):
            self.phase = "Nothing to update"
        return {"phase": self.phase, "n": self.n, "total": self.total, "line": l[:200]}


def follow(proc=None) -> None:
    prog = Progress()
    pos = 0
    tail = ""
    while True:
        try:
            with open(UPDATE_LOG, errors="replace") as f:
                f.seek(pos)
                chunk = f.read()
                pos = f.tell()
        except OSError:
            chunk = ""
        tail += chunk
        *lines, tail = tail.split("\n")
        for line in lines:
            step = prog.feed(line)
            if step:
                print(json.dumps(step), flush=True)
        alive = proc.poll() is None if proc is not None else update_pid() != 0
        if not alive and not chunk:
            break
        time.sleep(0.3)
    data = load()
    result = finish(data)
    if result.get("ok"):
        print(json.dumps({"phase": "Checking again", "n": 0, "total": 0, "line": ""}), flush=True)
        data["updates"] = check_updates()
    save(data)
    print(json.dumps({"done": True, **result}), flush=True)


def upgrade() -> None:
    if update_pid():
        return follow()
    if tasks.PASSWORD is None:
        print(json.dumps({"done": True, "ok": False, "message": "Your password is needed."}), flush=True)
        return
    if Path("/var/lib/pacman/db.lck").exists():
        busy = run(["pgrep", "-x", "pacman"], 5).returncode == 0
        print(json.dumps({"done": True, "ok": False, "terminal": not busy, "message":
              "Another install or update is running: wait for it to finish." if busy else
              "pacman's lock file was left behind by an update that did not finish "
              "(/var/lib/pacman/db.lck). If nothing else is installing, remove it: sudo rm /var/lib/pacman/db.lck"}),
              flush=True)
        return
    STATE.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(UPDATE_LOG, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    script = ("LC_ALL=C pacman -Syu --noconfirm --noprogressbar --color never; "
              f'echo "{EXIT_MARK}$?"')
    proc = subprocess.Popen(["sudo", "-S", "-k", "-p", "", "--", "/bin/sh", "-c", script],
                            stdin=subprocess.PIPE, stdout=fd, stderr=fd, start_new_session=True, text=True)
    os.close(fd)
    try:
        proc.stdin.write(tasks.PASSWORD + "\n")
        proc.stdin.close()
    except OSError:
        pass
    st = tasks.stat(proc.pid)
    if st is not None:
        UPDATE_RUN.write_text(f"{proc.pid} {st['start']}")
    follow(proc)


# ---- status ---------------------------------------------------------------------------------
def status() -> dict:
    data = load()
    if UPDATE_RUN.exists() and not update_pid():      # it ended while Settings was closed
        finish(data)
        save(data)
    return {
        "upgrading": update_pid() != 0,
        "lastUpdate": data.get("lastUpdate"),
        "ok": True,
        "firewall": firewall(),
        "listening": listening(),
        "ssh": ssh_server(),
        "updates": data.get("updates"),
        "autolock": autolock(),
        "hardening": hardening(),
        "encryption": encrypted_root(),
        "secureBoot": secure_boot(),
        "guard": {"time": data.get("guardTime"), "changes": data.get("changes", []),
                  "events": data.get("events", {}), "baseline": isinstance(data.get("baseline"), dict)},
        "scan": data.get("scan"),
        "tools": {t: have(t) for t in ("ufw", "arch-audit", "checkupdates", "ss")},
    }


def login() -> None:
    data = load()
    g = guard(data)
    if not data.get("updates") or int(time.time()) - int(data["updates"].get("time", 0)) > DAY:
        try:
            os.nice(10)                        # stay out of the way while you start working
        except OSError:
            pass
        data["updates"] = check_updates()
    save(data)
    stop_old_idle()
    news = []
    if g["changes"]:
        news.append(f"{len(g['changes'])} change(s) to what starts or listens on this computer")
    failed = data.get("events", {}).get("failed", [])
    remote = [f for f in failed if f.get("remote")]
    if remote:                                   # someone tried from the network
        news.append(f"{len(remote)} failed SSH login attempt(s) from the network")
    elif len(failed) >= 3:                       # one or two typos are just typos
        news.append(f"{len(failed)} failed password attempts on this computer")
    holes = [h for h in data["updates"].get("holes", []) if h.get("fix")]
    if holes:
        news.append(f"{len(holes)} package(s) with a known security hole have a fix")
    if news:
        notify("Yakushi Guard: " + "; ".join(news) + ". Open Settings -> Security (SUPER + I).")


def main() -> None:
    a = tasks.take_password(sys.argv[1:])
    try:
        if a == ["status"]:
            emit(status())
        elif a == ["updates"]:
            data = load()
            data["updates"] = check_updates()
            save(data)
            emit({"ok": True, "updates": data["updates"]})
        elif a == ["login"]:
            login()
        elif a == ["guard"]:
            data = load()
            g = guard(data)
            save(data)
            emit({"ok": True, **g})
        elif len(a) == 2 and a[0] == "accept":
            data = load()
            accept(data, a[1])
            save(data)
            emit({"ok": True, "message": "Taken as yours."})
        elif a == ["seen"]:
            data = load()
            clear_events(data)
            save(data)
            emit({"ok": True})
        elif len(a) == 2 and a[0] == "firewall" and a[1] in ("on", "off"):
            emit(set_firewall(a[1] == "on"))
        elif a == ["ssh", "off"]:
            emit(ssh_off())
        elif len(a) == 2 and a[0] == "harden" and a[1] in ("on", "off"):
            emit(set_hardening(a[1] == "on"))
        elif len(a) == 2 and a[0] == "autolock":
            emit(set_autolock(a[1]))
        elif a == ["upgrade"]:
            upgrade()
        elif a == ["follow"]:
            follow()
        elif a == ["scan"]:
            emit(deep_scan())
        else:
            emit({"ok": False, "message": "usage: status | updates | login | guard | accept <key>|all | seen | "
                                          "firewall on|off | ssh off | harden on|off | autolock <min>|off | scan | upgrade | follow"})
    except Exception as e:                       # always answer the page
        emit({"ok": False, "message": f"Unexpected error: {e}"})


if __name__ == "__main__":
    main()
