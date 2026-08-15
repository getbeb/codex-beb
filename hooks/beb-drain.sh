#!/bin/sh
# beb-drain — announce waiting beb mail at a codex turn boundary. No
# dependencies beyond a POSIX shell and beb itself.
#
# Codex hooks are synchronous, async output is discarded, and no rewake
# primitive exists, so this never waits and never watches: an instant
# `beb list` and whatever stands unread is announced.
#
#   - SessionStart: catch up on mail that arrived while codex was away.
#   - Stop: announce mail that landed during the turn, at the boundary.
#
# It never consumes: the cursor moves only by the agent running
# `beb read` itself, so the announcement repeats at each boundary until
# reading makes it stop being true. Waking a truly idle codex is NOT
# possible from a hook (openai/codex#20312) — see README.
#
# Codex injects differently per event, so the event is passed as $1.
# No mail, or no identity here, is a silent no-op.
set -u
BEB="${BEB_BIN:-beb}"
event="${1:-stop}"
input=$(cat 2>/dev/null || true)

# beb 0.6.0 stopped resolving the working directory: BEB_IDENTITY is the
# only thing it reads. A hook is its own short-lived process, so nothing
# it exports can outlive it -- codex offers no per-session env file, the
# way Claude Code offers CLAUDE_ENV_FILE. This hook can pin itself and
# only itself.
#
# Which splits the two cases, and the announcement has to say which one
# it is, because the agent is the one told to run `beb read`:
#
#   BEB_IDENTITY already set — it came from codex's environment, and
#   codex passes that through to the shell the agent runs commands in
#   (shell_environment_policy). The agent can run `beb read` bare.
#
#   unset — nothing but this process knows the answer. The hook falls
#   back to the session's directory for its own `list`, and names that
#   directory in the instruction, because a bare `beb read` from the
#   agent would answer "BEB_IDENTITY is not set" and it would be this
#   announcement's fault.
#
# The fix an operator can make once is in the README: launch codex with
# BEB_IDENTITY set, and every command in the session inherits it.
if [ -n "${BEB_IDENTITY:-}" ]; then
    pin=""
else
    dir=$(printf '%s' "$input" |
        sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
    [ -n "$dir" ] || dir=$PWD
    export BEB_IDENTITY="$dir"
    pin="BEB_IDENTITY=$dir "
fi

# A Stop caused by our own block continuation is marked by codex with
# stop_hook_active; never block it again. One announcement per ordinary
# Stop, and mail the agent declines to read waits for the next boundary
# instead of this hook manufacturing one — codex's own anti-loop
# contract for Stop hooks.
case "$event" in
sessionstart | SessionStart) ;;
*)
    active=$(printf '%s' "$input" |
        sed -n 's/.*"stop_hook_active"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p')
    [ "$active" = true ] && exit 0
    ;;
esac

unread=$("$BEB" list 2>/dev/null) || exit 0
[ -n "$unread" ] || exit 0

# JSON-encode the list as one string value. No jq: one awk pass — the
# sed `N;$!ba` slurp idiom silently drops single-line input on BSD sed,
# which is exactly the common case. Order matters: backslash first.
esc=$(printf '%s' "$unread" | awk 'BEGIN{ORS=""}
  { gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t");
    if (NR>1) printf "\\n"; printf "%s", $0 }')

# The pin is a path, and a path can hold the two bytes that end a JSON
# string. Escaped the same way and in the same order as the listing.
pinesc=$(printf '%s' "$pin" | awk 'BEGIN{ORS=""} { gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); printf "%s", $0 }')

msg='[beb] mail waits:\n'"$esc"'\nread with: '"$pinesc"'beb read'

case "$event" in
sessionstart | SessionStart)
    printf '%s%s%s\n' \
        '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"' \
        "$msg" \
        '"}}'
    ;;
*)
    printf '%s%s%s\n' \
        '{"decision":"block","reason":"' \
        "$msg" \
        '"}'
    ;;
esac
