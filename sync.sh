#!/usr/bin/env bash
# Pull the live uConsole tweak files from the system into this repo so they can
# be committed. Run this after changing any of them on the system, then
# `git add -A && git commit`. Read-only on the system (no sudo: all sources are
# world-readable).
set -eu
cd "$(dirname "$0")"

copy() { mkdir -p "$(dirname "$2")"; cp -a "$1" "$2"; }

# --- home ---
copy ~/.tmux.conf     home/.tmux.conf
copy ~/.bash_profile  home/.bash_profile
for f in brightness-status eco-status net-marquee-trigger uconsole-eco \
         network-status cm5-temp battery-status tmux-system-status \
         uconsole-trackball-scroll.py \
         kbdlayoutd kbd-status uconsole-mode \
         volume-control volume-status uconsole-splash; do
  copy ~/.local/bin/"$f" home/.local/bin/"$f"
done

# --- user systemd services ---
copy ~/.config/systemd/user/uconsole-trackball-scroll.service \
     home/.config/systemd/user/uconsole-trackball-scroll.service
copy ~/.config/systemd/user/kbdlayoutd.service \
     home/.config/systemd/user/kbdlayoutd.service

# --- /usr/local/bin (root-owned scripts) ---
for f in ucon-brightness power-event triggerhappy-watchdog uconsole-powerd uconsole-router tmux-resurrect-save; do
  copy /usr/local/bin/"$f" usr/local/bin/"$f"
done

# --- /etc ---
copy /etc/uconsole-power.conf                                  etc/uconsole-power.conf
copy /etc/default/console-setup                               etc/default/console-setup
copy /etc/triggerhappy/triggers.d/brightness.conf            etc/triggerhappy/triggers.d/brightness.conf
copy /etc/systemd/system/triggerhappy.service.d/override.conf etc/systemd/system/triggerhappy.service.d/override.conf
copy /etc/systemd/system/triggerhappy-watchdog.service       etc/systemd/system/triggerhappy-watchdog.service
copy /etc/systemd/system/uconsole-powerd.service             etc/systemd/system/uconsole-powerd.service
copy /etc/systemd/system/tmux-resurrect-save.service         etc/systemd/system/tmux-resurrect-save.service
copy /etc/systemd/system/tmux-resurrect-save.timer           etc/systemd/system/tmux-resurrect-save.timer
copy /etc/NetworkManager/dispatcher.d/90-net-marquee         etc/NetworkManager/dispatcher.d/90-net-marquee
copy /etc/udev/rules.d/90-power-marquee.rules                etc/udev/rules.d/90-power-marquee.rules
copy /etc/udev/rules.d/91-triggerhappy-restart.rules        etc/udev/rules.d/91-triggerhappy-restart.rules
copy /etc/tmpfiles.d/eco-event.conf                         etc/tmpfiles.d/eco-event.conf
copy /etc/tmpfiles.d/net-status.conf                        etc/tmpfiles.d/net-status.conf
copy /etc/tmpfiles.d/power-event.conf                       etc/tmpfiles.d/power-event.conf

# --- docs ---
copy ~/Documents/uconsole-power-plan.md docs/uconsole-power-plan.md

echo "synced live system files into repo."
