if [ -f "$HOME/.profile" ]; then
    . "$HOME/.profile"
fi

if [ -z "$TMUX" ] && [ "$(tty)" = "/dev/tty1" ]; then
    # Prompted session restore: once per boot, only if a snapshot exists and no
    # tmux server is running yet (tmpfs marker is cleared on reboot).
    _rs_last="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect/last"
    _rs_marker="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/uconsole-restore-asked"
    if [ ! -e "$_rs_marker" ] && [ -e "$_rs_last" ] && ! tmux has-session 2>/dev/null; then
        : > "$_rs_marker"
        printf 'Restore previous session? [Y/n] '
        read -r _rs_ans
        case "$_rs_ans" in
            [Nn]*) ;;
            *) tmux new-session -d -s _bootstrap 2>/dev/null
               tmux run-shell "$HOME/.tmux/plugins/tmux-resurrect/scripts/restore.sh"
               tmux kill-session -t _bootstrap 2>/dev/null
               tmux has-session -t uconsole 2>/dev/null && exec tmux attach -t uconsole ;;
        esac
    fi
    exec tmux new -A -s uconsole
fi

# Show the uConsole banner in each new interactive tmux window/pane.
if [[ $- == *i* ]] && [ -n "$TMUX" ] && [ -t 1 ] && [ -x "$HOME/.local/bin/uconsole-splash" ]; then
    "$HOME/.local/bin/uconsole-splash"
fi

. "$HOME/.atuin/bin/env"
