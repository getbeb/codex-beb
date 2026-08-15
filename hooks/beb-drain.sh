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
# beb 0.6.0 stopped resolving the working directory: BEB_IDENTITY is the
# only thing it reads. Codex hands a hook no identity of its own, but a
# hook process inherits codex's environment and its directory, so the
# directory codex was started in is still the answer -- it just has to
# be named now. An ambient declaration wins, which is how the README
# already says to run codex from somewhere else.
export BEB_IDENTITY="${BEB_IDENTITY:-$PWD}"
event="${1:-stop}"
input=$(cat 2>/dev/null || true)

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

msg='[beb] mail waits:\n'"$esc"'\nread with: beb read'

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
