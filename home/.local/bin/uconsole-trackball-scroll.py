#!/usr/bin/env python3
"""Map uConsole trackball vertical motion (REL_Y) to tmux scroll (copy-mode).

The trackball only emits REL_X/REL_Y (no wheel events), and on a bare
framebuffer console there is no pointer, so the ball is otherwise unused.
We accumulate REL_Y and drive tmux copy-mode: roll up -> scroll back,
roll down -> scroll forward (auto-exits copy-mode at the bottom).
Targets the pane attached to the real console client, so it also works when
Codex itself is running under sudo and root has a different tmux socket.
"""
import os
import subprocess
import time

from evdev import InputDevice, list_devices, ecodes

DEVICE_NAME = "ClockworkPI uConsole Mouse"
UNITS_PER_LINE = 8        # smaller = more sensitive (REL_Y units per scrolled line)
MAX_LINES = 12            # clamp one burst so a fast flick can't jump miles
INVERT = False            # True -> roll up scrolls forward instead of back
TMUX = "/usr/bin/tmux"
TMUX_SOCKET = os.environ.get("UCONSOLE_TMUX_SOCKET", "/tmp/tmux-1000/default")
TMUX_CLIENT = os.environ.get("UCONSOLE_TMUX_CLIENT", "/dev/tty1")
ENV = dict(os.environ)
ENV.setdefault("TMUX_TMPDIR", "/tmp")


def tmux_args(*args):
    return [TMUX, "-S", TMUX_SOCKET, *args]


def tmux_run(*args, **kwargs):
    return subprocess.run(tmux_args(*args), env=ENV, **kwargs)


def active_pane():
    """Return the pane id attached to the console client."""
    r = tmux_run(
        "display-message", "-c", TMUX_CLIENT, "-p", "#{pane_id}",
        capture_output=True, text=True, check=False,
    )
    pane = r.stdout.strip()
    return pane if pane.startswith("%") else None


def pane_state(pane):
    """Return (mouse_aware, width, height, pid) for pane."""
    r = subprocess.run(
        tmux_args("display-message", "-t", pane, "-p",
                  "#{mouse_any_flag} #{pane_width} #{pane_height} #{pane_pid}"),
        env=ENV, capture_output=True, text=True, check=False,
    )
    parts = r.stdout.split()
    if len(parts) != 4:
        return (False, 80, 24, None)
    return (parts[0] == "1", int(parts[1]), int(parts[2]), int(parts[3]))


def descendant_commands(root_pid):
    """Return command names under root_pid, including grandchildren."""
    if root_pid is None:
        return set()
    children = {}
    commands = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            with open(f"/proc/{pid}/stat") as fh:
                stat = fh.read().split()
            ppid = int(stat[3])
            with open(f"/proc/{pid}/comm") as fh:
                commands[pid] = fh.read().strip()
        except (OSError, ValueError, IndexError):
            continue
        children.setdefault(ppid, []).append(pid)

    seen = set()
    stack = [root_pid]
    while stack:
        pid = stack.pop()
        for child in children.get(pid, []):
            if child in seen:
                continue
            seen.add(child)
            stack.append(child)
    return {commands[pid] for pid in seen if pid in commands}


def send_page_keys(pane, up, count):
    key = "PPage" if up else "NPage"
    tmux_run(
        "send-keys", "-t", pane, "-N", str(count), key,
        check=False,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


def find_device():
    for path in list_devices():
        try:
            dev = InputDevice(path)
        except (OSError, PermissionError):
            continue
        if dev.name == DEVICE_NAME:
            return dev
        dev.close()
    return None


def scroll(lines, up):
    pane = active_pane()
    if pane is None:
        return
    count = min(abs(lines), MAX_LINES)
    n = str(count)
    mouse_aware, w, h, pid = pane_state(pane)
    if "codex" in descendant_commands(pid):
        send_page_keys(pane, up, count)
        return
    if mouse_aware:
        # App has SGR mouse tracking on: feed it real wheel events so it
        # scrolls itself (claude, ssh TUIs, less -with-mouse, etc.).
        # SGR wheel: ESC [ < 64 ; col ; row M (64=up, 65=down).
        btn = 64 if up else 65
        seq = "\x1b[<%d;%d;%dM" % (btn, max(w // 2, 1), max(h // 2, 1))
        tmux_run(
            "send-keys", "-t", pane, "-l", "--", seq * count,
            check=False,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    elif up:
        # Plain shell: enter copy-mode (-e auto-exits at the bottom) and scroll.
        tmux_run(
            "copy-mode", "-e", "-t", pane, ";",
            "send-keys", "-t", pane, "-X", "-N", n, "scroll-up",
            check=False,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    else:
        # Plain shell, scrolling forward: only meaningful if already in copy-mode.
        tmux_run(
            "if-shell", "-t", pane, "-F", "#{pane_in_mode}",
            "send-keys -t %s -X -N %s scroll-down" % (pane, n),
            check=False,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )


def run(dev):
    print("listening on %s (%s)" % (dev.path, dev.name), flush=True)
    acc = 0
    for event in dev.read_loop():
        if event.type != ecodes.EV_REL or event.code != ecodes.REL_Y:
            continue
        # evdev: negative REL_Y == ball rolled up.
        acc += -event.value if not INVERT else event.value
        if abs(acc) >= UNITS_PER_LINE:
            lines = int(acc / UNITS_PER_LINE)
            scroll(lines, up=(lines > 0))
            acc -= lines * UNITS_PER_LINE


def main():
    while True:
        dev = find_device()
        if dev is None:
            time.sleep(2)
            continue
        try:
            run(dev)
        except OSError:
            try:
                dev.close()
            except Exception:
                pass
            time.sleep(1)


if __name__ == "__main__":
    main()
