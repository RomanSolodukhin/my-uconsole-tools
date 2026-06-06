#!/usr/bin/env bash
# Deploy the uConsole tweaks from this repo onto the system (e.g. a fresh image).
# Idempotent. Needs sudo for /etc and /usr/local/bin. Run from the repo root.
set -eu
cd "$(dirname "$0")"

echo ">> home"
install -Dm644 home/.tmux.conf    "$HOME/.tmux.conf"
install -Dm644 home/.bash_profile "$HOME/.bash_profile"
for f in home/.local/bin/*; do
  install -Dm755 "$f" "$HOME/.local/bin/$(basename "$f")"
done

echo ">> /usr/local/bin"
for f in usr/local/bin/*; do
  sudo install -Dm755 "$f" "/usr/local/bin/$(basename "$f")"
done

echo ">> /etc (configs 0644)"
( cd etc && find . -type f -print0 | while IFS= read -r -d '' f; do
    sudo install -Dm644 "$f" "/etc/$f"
  done )
# NetworkManager dispatcher scripts must be executable
sudo chmod 0755 /etc/NetworkManager/dispatcher.d/90-net-marquee

echo ">> shutdown-warning sound (generated, not vendored)"
sudo mkdir -p /usr/local/share/uconsole
[ -f /usr/local/share/uconsole/shutdown-warn.wav ] || sudo ffmpeg -y -loglevel error \
  -f lavfi -i "sine=frequency=880:duration=0.18" \
  -f lavfi -i "sine=frequency=660:duration=0.18" \
  -f lavfi -i "sine=frequency=440:duration=0.22" \
  -f lavfi -i "anullsrc=r=44100:cl=mono:d=0.07" \
  -f lavfi -i "anullsrc=r=44100:cl=mono:d=0.07" \
  -filter_complex "[0][3][1][4][2]concat=n=5:v=0:a=1,volume=1.0" \
  /usr/local/share/uconsole/shutdown-warn.wav

echo ">> tmux-resurrect plugin"
[ -d "$HOME/.tmux/plugins/tmux-resurrect" ] || \
  git clone --depth 1 https://github.com/tmux-plugins/tmux-resurrect "$HOME/.tmux/plugins/tmux-resurrect"

echo ">> reload + enable"
sudo systemctl daemon-reload
sudo udevadm control --reload-rules
sudo systemd-tmpfiles --create
sudo setupcon --force --save 2>/dev/null || true   # console font
sudo systemctl enable --now \
  triggerhappy.service triggerhappy-watchdog.service \
  uconsole-powerd.service tmux-resurrect-save.timer

echo "done. Console font applies on next login/reboot; default economy pref starts 'off'."
