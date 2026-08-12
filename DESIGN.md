# codex-beb

beb mail announced at codex's turn boundaries.

beb delivers signed messages into a mailbox and never interrupts
anyone; wake policy belongs to the runtime. codex's runtime offers
less to work with than pi's or Claude Code's, and this plugin is
honest about that: mail is announced at the two boundaries codex
has, and waking a truly idle codex is not this plugin's to promise.

## The two primitives it joins

From beb, one verb: `list`, which shows what stands unread and moves
nothing. Announcement needs nothing else.

From codex, two synchronous hook seams. SessionStart can hand back
`additionalContext`; Stop can return `{"decision": "block"}` whose
reason codex takes as a continuation prompt and acts on. That is the
whole surface: codex hooks cannot wait (a blocking hook freezes the
turn), async hooks run but their output is discarded, and no rewake
primitive exists (openai/codex#20312, open). So there is no
doorbell, and this plugin does not fake one.

## Invariants

1. codex-beb never consumes mail. It announces; the agent reads.
   The cursor moves only by the agent running `beb read` itself.
2. Boundaries only. SessionStart catches up on mail that arrived
   while codex was away; Stop announces mail that landed during the
   turn. Nothing lands mid-turn, and nothing wakes an idle codex.
3. Injected text is bounded: the unread `list` lines and the verb
   to act on them, never a body.
4. No state, no dependencies: POSIX shell and beb itself. JSON is
   encoded in one awk pass, no jq.
5. No identity, no activity. A directory without a `.beb` makes the
   hook exit silently.

## Behavior

One script, told the event by its argument. Unread mail becomes the
same announcement every beb integration speaks:

    [beb] mail waits:
    3  frontend
    4  ssh-ed25519 AAAA...
    read with: beb read

At SessionStart it rides in as `additionalContext`. At Stop it is
the block reason, which codex treats as a continuation: the agent
reads at the boundary its own turn created. An empty list is a
silent exit either way, and the announcement repeats at each
boundary until the agent reads, because reading is what makes it
stop being true.

## Out of scope

Waking an idle codex (the pane supervisor's or app-server's job),
consuming on the agent's behalf, delivering bodies, watching
anything. Whatever codex-beb cannot learn from one `beb list` at a
boundary, it does not know.

## Design test

Every proposed feature answers one question:

> Is this necessary to announce waiting mail at a codex turn
> boundary?
