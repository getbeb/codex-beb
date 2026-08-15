#!/usr/bin/env bash
# Standalone tests for the drain hook. Run: bash tests/test.sh
# BEB_BIN overrides the beb binary.
set -u

HERE=$(cd "$(dirname "$0")/.." && pwd)
DRAIN=$HERE/hooks/beb-drain.sh
BEB=${BEB_BIN:-beb}
export BEB_BIN=$BEB
# An ambient identity from the developer's own shell would override the
# default the hook computes, which is the thing under test here.
unset BEB_IDENTITY

have=$("$BEB" --version 2>/dev/null | awk '{print $2}')
[ -n "$have" ] || { echo "not ok - no beb on PATH or in BEB_BIN"; exit 1; }
gate=0.6.0
older=$(printf '%s\n%s\n' "$gate" "$have" | sort -t. -k1,1n -k2,2n -k3,3n | head -n 1)
if [ "$have" != "$gate" ] && [ "$older" = "$have" ]; then
    echo "not ok - beb $have is older than $gate (identity, subjects)"
    exit 1
fi

# Identity is named, never inherited from the working directory.
b() { d=$1; shift; BEB_IDENTITY="$S/$d" "$BEB" "$@"; }

S=$(mktemp -d)
export XDG_CONFIG_HOME=$S/config XDG_DATA_HOME=$S/data
mkdir -p "$S/config/beb" "$S/a" "$S/b" "$S/bare"

n=0
OUT=$S/out.txt
ERR=$S/err.txt
ok() { n=$((n + 1)); echo "ok $n - $1"; }
die() {
    echo "not ok - $1"
    echo "--- stdout ---"; cat "$OUT" 2>/dev/null
    echo "--- stderr ---"; cat "$ERR" 2>/dev/null
    exit 1
}

(cd "$S/a" && "$BEB" init >/dev/null) || die "init a"
(cd "$S/b" && "$BEB" init >/dev/null) || die "init b"
A=$(b a whoami 2>/dev/null)
echo "tester $(b b whoami 2>/dev/null)" >"$S/config/beb/known_signers"

# Hook input as codex sends it: plain Stop, and a Stop caused by a Stop
# hook's own continuation.
IN='{"session_id":"t","stop_hook_active":false}'
INA='{"session_id":"t","stop_hook_active":true}'

drain() { # <dir> <event> <input>
    printf '%s' "$3" | (cd "$S/$1" && "$DRAIN" "$2") >"$OUT" 2>"$ERR"
}

drain a stop "$IN" || die "empty stop failed"
test -s "$OUT" && die "spoke with no mail"
ok "no mail: silent"

drain bare stop "$IN" || die "no-identity failed"
test -s "$OUT" && die "spoke without identity"
ok "no identity: silent"

b b send "$A" --subject "one line" --body x >/dev/null 2>&1 || die "send"

drain a sessionstart "$IN" || die "sessionstart failed"
python3 -c "
import json
d=json.load(open('$OUT'))
o=d['hookSpecificOutput']
assert o['hookEventName']=='SessionStart', o
c=o['additionalContext']
assert c.startswith('[beb] mail waits:'), c
assert 'read with: beb read' in c, c
assert c.splitlines()[1].startswith('1  ') and c.splitlines()[1].endswith('tester'), c
" || die "sessionstart shape: $(cat "$OUT")"
ok "sessionstart: valid JSON additionalContext with the announcement"

drain a stop "$IN" || die "stop failed"
python3 -c "
import json
d=json.load(open('$OUT'))
assert d['decision']=='block', d
r=d['reason']
assert r.startswith('[beb] mail waits:') and 'read with: beb read' in r, r
" || die "stop shape: $(cat "$OUT")"
ok "stop with unread: valid JSON block with the announcement"

drain a stop "$INA" || die "active stop failed"
test -s "$OUT" && die "blocked a stop our own continuation caused"
ok "stop_hook_active: never block again, codex's anti-loop honored"

drain a sessionstart "$INA" || die "active sessionstart failed"
grep -q "mail waits" "$OUT" || die "sessionstart wrongly muted by stop_hook_active"
ok "stop_hook_active does not mute SessionStart"

drain a stop "$IN" && cp "$OUT" "$S/out2.txt" || die "rerun failed"
drain a stop "$IN" || die "rerun 2 failed"
cmp -s "$OUT" "$S/out2.txt" || die "not idempotent"
ok "never consumes: rerun announces the same mail"

# The single-line case is the BSD-sed trap of old; hostile bytes must
# never break the JSON envelope.
b b send "$A" --subject 'quotes " and \ backslashes' --body x >/dev/null 2>&1 || die "send hostile"
drain a stop "$IN" || die "hostile stop failed"
python3 -c "import json; json.load(open('$OUT'))" || die "hostile bytes broke JSON: $(cat "$OUT")"
ok "JSON survives arbitrary list bytes, single-line included"

{ b a read >/dev/null 2>&1 && b a read >/dev/null 2>&1; } || die "reads"
drain a stop "$IN" || die "post-read stop failed"
test -s "$OUT" && die "announced after reading"
ok "after the agent reads, boundaries go quiet"

echo "all $n tests passed"
