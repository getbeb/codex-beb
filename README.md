# codex-beb

beb mail announced at Codex turn boundaries.

[beb](https://getbeb.dev/) delivers signed messages into a mailbox and
never interrupts anyone. codex-beb announces waiting mail when a Codex
session starts and when a turn ends.

Codex cannot currently be woken by a hook while truly idle.

## Install

```sh
codex plugin marketplace add getbeb/codex-beb
codex plugin add codex-beb@codex-beb
```

Codex does not automatically trust installed hooks; review and trust
them before use.

Requires beb 0.10.0 or newer:

```sh
curl -fsSL https://getbeb.dev/install.sh | sh
```

## Use

Prefer launching Codex with the identity named:

```sh
BEB_IDENTITY=~/work/backend codex
```

That pins the identity for commands the agent runs, so `beb read` works
directly.

Running Codex from an identity directory works too:

```sh
cd ~/work/backend    # has .beb, from beb init backend
codex
```

In that case codex-beb carries the identity explicitly in its read
instruction.

Unread mail is announced at a session start or turn boundary:

```text
[beb] mail waits:
4  12m  schema drift    ...Y5ODcn2+
3  4h   deploy blocked  frontend
read with: beb read
```

codex-beb never consumes mail: the cursor moves only when the agent runs
`beb read`. If no beb identity can be resolved, the plugin stays quiet.

## The idle gap

Codex hooks can announce mail at session and turn boundaries, but they
cannot start a new turn in an idle session. Mail arriving while Codex is
idle therefore waits until the next boundary.

If true idle wake is required, it has to come from a layer outside the
hook system, such as a supervisor or the app-server.

See [openai/codex#20312](https://github.com/openai/codex/issues/20312)
for the missing native wake primitive.

## How it works

codex-beb runs a small POSIX shell hook at SessionStart and Stop. It
checks `beb list` and announces unread mail without advancing the
cursor.

See [DESIGN.md](DESIGN.md) for hook behavior and loop-prevention
details.

## License

MIT
