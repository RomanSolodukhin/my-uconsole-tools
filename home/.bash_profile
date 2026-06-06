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

# uConsole startup splash — print once per tmux session, in the first shell.
# Each tmux pane is a login shell that re-reads this file, so a per-session
# flag keeps the banner from reappearing in every new window/pane.
if [ -n "$TMUX" ] && [ -x "$HOME/.local/bin/uconsole-splash" ]; then
    _sp_sid=$(tmux display-message -p '#{session_id}' 2>/dev/null)
    _sp_flag="${TMPDIR:-/tmp}/uconsole-splash.${_sp_sid#\$}"
    if [ -n "$_sp_sid" ] && [ ! -e "$_sp_flag" ]; then
        : > "$_sp_flag"
        "$HOME/.local/bin/uconsole-splash"
    fi
    unset _sp_sid _sp_flag
fi
