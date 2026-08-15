# codex-beb

beb mail announced at codex's turn boundaries.

[beb](https://getbeb.dev) delivers signed messages into a mailbox and
never interrupts anyone; wake policy belongs to the runtime. codex's
hook surface is smaller than pi's or Claude Code's, and this plugin
is honest about it: mail waiting at a session start or turn end is
announced there, and waking a truly idle codex is not something a
codex hook can do.

| capability | codex-beb |
| --- | --- |
| catch-up at session start | yes |
| announce at turn end | yes |
| wake an idle session | no (see below) |

## Install

```sh
codex plugin marketplace add getbeb/codex-beb
codex plugin add codex-beb@codex-beb
```

Installing does not auto-trust hooks; review and trust them, or pass
`--dangerously-bypass-hook-trust` for a single run. beb itself must
be on PATH, version 0.3.0 or newer (the first release carrying the
full integration contract, `BEB_IDENTITY` included):

```sh
curl -fsSL https://getbeb.dev/install.sh | sh
```

## Use

Run codex in a directory that is a beb identity:

```sh
cd ~/work/backend    # has .beb, from beb init
codex

# or, for a codex launched where cd is not available:
BEB_IDENTITY=~/work/backend codex
```

Mail standing unread at a boundary is announced:

```
[beb] mail waits:
3  frontend
4  ssh-ed25519 AAAA...
read with: beb read
```

At SessionStart it arrives as additional context; at Stop it arrives
as a continuation — once: a Stop caused by that continuation is
marked by codex (`stop_hook_active`) and never blocked again, so
declined mail waits instead of looping. codex-beb never consumes
mail: the cursor moves only when the agent runs `beb read` itself.
If beb cannot resolve an identity, the hook exits silently. Identity
is `BEB_IDENTITY`, which the hook defaults to the directory codex was
started in; beb itself has read nothing else since 0.6.0.

## The idle gap

Codex hooks are synchronous (a blocking hook freezes the turn),
async hook output is discarded, and no rewake primitive exists;
codex's own tracker confirms the gap (openai/codex#20312). So mail
arriving while codex sits idle waits until the next boundary, which
is beb's promise anyway: mail waits. If you need a true idle wake,
put codex under a pane supervisor or drive it via the app-server;
that layer, not a hook, is where waking belongs.

## How it works

One POSIX shell script, no dependencies beyond beb itself, wired to
SessionStart and Stop. It asks `beb list`, JSON-encodes the
announcement in one awk pass (no jq), and exits silently when
nothing is unread. The full reasoning is in [DESIGN.md](DESIGN.md).

## License

MIT
