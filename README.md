# uConsole tweaks

Personal customizations for a **ClockworkPI uConsole (CM5)**, Debian 12 (bookworm, "Rex"
image), running on the **bare framebuffer console** (no X/Wayland) inside **tmux**.

The repo mirrors the filesystem: each file lives under the path it deploys to.

```
home/.tmux.conf, home/.bash_profile, home/.local/bin/*   -> $HOME/...
usr/local/bin/*                                           -> /usr/local/bin/...
etc/**                                                    -> /etc/**
docs/uconsole-power-plan.md                               -> design doc
```

- `./sync.sh`   — copy the live system files **into** this repo (run before committing).
- `./install.sh` — deploy the repo **onto** a system (idempotent; needs sudo).

`tmux-resurrect` is a third-party plugin (not vendored); `install.sh` git-clones it into
`~/.tmux/plugins/`.

## What's here

**Console / status bar**
- `etc/default/console-setup` — font `TerminusBold 28x14` (readable, Cyrillic).
- `home/.tmux.conf` — `status-right` assembled from the scripts below, cells joined by `▒`;
  also provides tmux bindings for volume control and a work-user window.
- `home/.local/bin/`: `tmux-system-status` (joins cells), `brightness-status` (`●N`),
  `network-status`, `cm5-temp` (`NN.N°`), `battery-status` (`↑/↓ NN%`), `eco-status` (`ECO`),
  `volume-control`/`volume-status` and `uconsole-splash`.

**Brightness keys** (Fn brightness → backlight 0–9)
- `usr/local/bin/ucon-brightness` — step with floor=1, instant status refresh.
- `etc/triggerhappy/triggers.d/brightness.conf` + `etc/systemd/system/triggerhappy.service.d/override.conf`
  (run thd as root).
- `usr/local/bin/triggerhappy-watchdog` + service — restart thd on `Error reading device`.
- `etc/udev/rules.d/91-triggerhappy-restart.rules` — restart thd when the keyboard
  (re-)appears (fixes boot race / MCU re-enumeration).

**Marquees** (scrolling status messages)
- Wi-Fi SSID on connect: `etc/NetworkManager/dispatcher.d/90-net-marquee`, `network-status`,
  `home/.local/bin/net-marquee-trigger` (replay at tmux session start).
- Power cable CHARGING/ON BATTERY: `etc/udev/rules.d/90-power-marquee.rules`,
  `usr/local/bin/power-event`, `battery-status`.
- tmpfiles for the `/run` event files: `etc/tmpfiles.d/{net-status,power-event,eco-event}.conf`.

**Trackball scroll** (no pointer on the bare console — repurpose the ball for scrolling)
- `home/.local/bin/uconsole-trackball-scroll.py` + `home/.config/systemd/user/uconsole-trackball-scroll.service`
  (user service; needs `python3-evdev`, user must be in group `input`).
- The daemon reads `/dev/input/event*` directly, so the user must be in the `input`
  group: `sudo usermod -aG input "$USER"` (log out/in for it to take effect).
- Reads the trackball's `REL_Y` directly (it never emits wheel events) and, per active pane:
  feeds real SGR wheel sequences to mouse-aware apps (claude, ssh TUIs, `less`) so they
  scroll themselves, or drives tmux `copy-mode` in a plain shell. Tunables (`UNITS_PER_LINE`,
  `MAX_LINES`, `INVERT`) at the top of the script.

**Economy mode** (see `docs/uconsole-power-plan.md` for the full design)
- `usr/local/bin/uconsole-powerd` + service — engine: on battery, when eco is on, CPU
  `powersave` + dim screen on input-idle; auto-shutdown when idle of input **and** network
  traffic (low/critical battery shuts down on input-idle alone); 60s warning cancellable by
  any input; saves the tmux session before poweroff.
- `etc/uconsole-power.conf` — all thresholds (`DRY_RUN=0` = real poweroff).
- `home/.local/bin/uconsole-eco` — `on|off|toggle|status` (persistent pref in
  `~/.config/uconsole/economy`, not versioned).
- Session save/restore: `usr/local/bin/tmux-resurrect-save` +
  `etc/systemd/system/tmux-resurrect-save.{service,timer}` (15-min autosave); restore prompt
  on boot lives in `home/.bash_profile`.

Kill switch for the economy engine: `sudo systemctl stop uconsole-powerd`.

**4G and one-shot GUI browser**
- `home/.local/bin/uconsole-4g-tui` (alias `4g-tui`) — whiptail UI for modem power,
  registration, data connections, SMS, USSD and calls.
- `usr/local/bin/uconsole-4g` + `uconsole-4g-cm4.sh` — CM4-specific GPIO power control;
  verify GPIO pins before using it on another uConsole revision.
- `home/.local/bin/browser` + `usr/local/bin/uconsole-start-gui-browser-once` — start or
  reuse a single rotated X11 browser session; `gui-clipboard-sync` bridges tmux and X11
  clipboard while it is running.

The 4G TUI requires `whiptail`, `mmcli`, `nmcli` and a working ModemManager setup.
The browser helpers require `startx`, Openbox, Firefox or Chromium, `sudo`, and optionally
`xclip`. The `tweb` launcher is intentionally not included: it belongs to the separate
`tweb-browser` application tree.
