---
phase: 14-live-log-streaming-terminal-watch-relay
reviewed: 2026-09-01T00:00:00Z
depth: deep
files_reviewed: 8
files_reviewed_list:
  - lib/spm_cache/web/events.rb
  - lib/spm_cache/web/read_models/runs.rb
  - lib/spm_cache/web/router.rb
  - lib/spm_cache/web/server.rb
  - lib/spm_cache/web/assets/log.js
  - lib/spm_cache/web/assets/index.html
  - lib/spm_cache/web/assets/styles.css
  - lib/spm_cache/core/run_log.rb
findings:
  critical: 2
  warning: 1
  info: 2
  total: 5
status: issues_found
---

# Phase 14: Code Review Report

**Reviewed:** 2026-09-01
**Depth:** deep (cross-file: Router → Events → Broadcaster/Tailer → log.js wire contract; RunLog → Sh/Watch call chains)
**Files Reviewed:** 8 production files (`bb35be4^..HEAD`)
**Status:** issues_found

## Summary

Reviewed the full live-log streaming spine end to end: `router.rb`'s SSE
route → `events.rb`'s `Broadcaster`/`Tailer`/`Client`/`PinnedFollow` →
`read_models/runs.rb`'s shared status derivation → `log.js`'s wire
consumption, plus the `run_log.rb` multi-writer buffering fix this phase
carries and the pre-existing installer lock sites `Runs.lock_state`
depends on for CP10 consistency.

The security posture (Host/Origin/token gates, path-traversal containment
on `Last-Event-ID` and `?run=`, XSS discipline in `log.js`, no client
clock, no timers, asset paths, filter-dims-never-hides, single switch
slot, banner-uses-displayed-run-not-event-field) all hold up under direct
inspection — no violations found in any of the pinned contracts listed
for this review. `run_log.rb`'s `[thread, stream]` buffer-keying change is
a correct, well-reasoned fix for the multi-writer race it documents; no
regression found.

Two BLOCKER-class defects were found, both in `events.rb`'s runtime
correctness rather than the security surface: (1) the pop loop's
`Queue#pop(timeout:)` call is incompatible with Ruby 3.1 — the gem's own
declared minimum and a CI-tested version — and silently misbehaves rather
than raising a clear error, breaking every SSE connection on that
runtime; (2) the tailer's very-first attach (and its post-prune-race
re-attach) skips already-on-disk content instead of replaying it the way
`switch_to` does, so an already-connected idle client never receives the
run identity or a switch notice when the first (or recovered) run
appears, and a narrow window of appended bytes can be permanently lost
between an early client's replay cutoff and the tailer's first tick.

## Critical Issues

### CR-01: `SizedQueue#pop(timeout:)` is not a Ruby-3.1-safe call — every SSE connection breaks on the gem's declared minimum Ruby

**File:** `lib/spm_cache/web/events.rb:378`
**Issue:**
`pop_loop`'s only blocking primitive is:
```ruby
item = client.queue.pop(timeout: timeout)
```
`Thread::SizedQueue#pop` only gained a `timeout:` keyword argument in
**Ruby 3.2** (the C implementation before that has no keyword-argument
parsing for `pop` at all). The gemspec declares
`spec.required_ruby_version = ">= 3.1.0"` and `.github/workflows/ci.yml`
runs the RSpec suite on the exact matrix `['3.1', '3.2', '3.3']` — Ruby
3.1 is both a declared-supported and CI-tested target.

This is not merely a version mismatch that raises a clear `ArgumentError`
— it silently miscompiles into the wrong call. Verified empirically
against a real Ruby 3.1.7 (Homebrew `ruby@3.1`, arm64):
```
$ ruby -e 'q = SizedQueue.new(5); t0 = Time.now
  begin
    q.pop(timeout: 2.0)
  rescue => e
    puts "#{e.class}: #{e.message} after #{Time.now - t0}s"
  end'
ThreadError: queue empty after 2.0e-05s
```
On 3.1, `pop(timeout: 2.0)` is absorbed as the single legacy positional
argument (`non_block`); a non-empty `Hash` is truthy, so the call
degenerates to `pop(true)` — a **non-blocking** pop — and raises
`ThreadError: queue empty` immediately instead of blocking. Since the
queue is empty for the entire idle period between deliveries (the normal
steady state of a live-tail connection), this fires on essentially every
SSE connection's very first idle interval. The `ThreadError` is not
rescued anywhere in `stream`/`pop_loop` (only `Errno::EPIPE`,
`Errno::ECONNRESET`, `IOError` are rescued at the `stream` method level),
so it escapes the WEBrick body proc unhandled on every connection.

This also explains why `spec/events_broadcaster_spec.rb`,
`spec/events_tailer_spec.rb`, and `spec/web_events_route_spec.rb` — which
all call `client.queue.pop(timeout: ...)` directly, and the route spec
drives a real HTTP request through `pop_loop` over a raw socket
(`poll_interval: 0.05, heartbeat_seconds: 0.25`) — would fail under the
Ruby 3.1 CI leg even though the suite is green under the current
dev-machine Ruby (3.2.3).

**Fix:** Use a version-safe pattern that works identically on 3.1–3.3,
e.g. drop the keyword and implement the timeout with `Timeout.timeout`
or a monitor/condvar, or gate on `RUBY_VERSION`. Simplest drop-in
replacement (no stdlib version straddling):
```ruby
require 'timeout'
# ...
def pop_with_timeout(queue, timeout)
  Timeout.timeout(timeout) { queue.pop }
rescue Timeout::Error
  nil
end
```
and call `pop_with_timeout(client.queue, timeout)` at events.rb:378 (and
the identical fallback pattern for any other production `pop(timeout:)`
call site introduced by this phase). Whatever mechanism is chosen, it
must be verified against actual Ruby 3.1, not merely Ruby 3.2+, since the
keyword silently changes meaning rather than erroring.

**Resolution:** Fixed. Added `Events.pop_with_timeout(queue, timeout)` --
a `Timeout.timeout { queue.pop }` wrapper that blocks on a plain
`queue.pop` (portable across 3.1-3.3) -- and switched the production call
site (`pop_loop`) plus the two specs that poke `client.queue.pop(timeout:
...)` directly on the same production `SizedQueue`
(`spec/events_broadcaster_spec.rb`, `spec/events_tailer_spec.rb`) to use
it. Verified against a real Ruby 3.1.7 (Homebrew `ruby@3.1`, arm64): the
raw `pop(timeout:)` call reproduces the `ThreadError: queue empty`
defect immediately; `pop_with_timeout` blocks for the full timeout on an
empty queue, returns immediately when an item is already queued, and
unblocks promptly when a producer delivers mid-wait.
**Commit:** `1127924` -- `fix(14-events): CR-01 make client queue pop timeout-safe on Ruby 3.1`

---

### CR-02: First tailer attach silently skips existing run content instead of replaying it — idle-connected clients never see the run start, and a narrow window of output is lost forever

**File:** `lib/spm_cache/web/events.rb:283-291` (`Tailer#discover`), `events.rb:305-312` (`Tailer#attach`), contrast with `events.rb:293-297` (`Tailer#switch_to`)
**Issue:**
```ruby
def discover
  newest = Dir.glob(File.join(@config.runs_dir, '*.jsonl')).sort.last
  if @path.nil?
    attach(newest, from_byte0: false) if newest   # <-- no publish, skips existing content
  elsif newest && newest > @path
    switch_to(newest)                              # <-- from_byte0: true + publish_switch
  end
end

def attach(path, from_byte0:)
  @path = path
  @prune_notified = false
  @offset = from_byte0 ? 0 : last_complete_line_offset(path)
  ...
end
```
When the tailer has never attached to anything yet (`@path.nil?` — true
at server boot before the first run exists, and again after the
`switch_to` rescue's `Errno::ENOENT` recovery resets `@path = nil`), the
new run is attached with `from_byte0: false`, i.e. `@offset` is set to
*skip every line already on disk* (`last_complete_line_offset`), and no
`Switch`/notice is published to the broadcaster. This differs from
`switch_to`, which always replays from byte 0 (`from_byte0: true`) *and*
publishes a `Switch` event.

The documented justification for skipping existing content
(`attach`'s comment: "only lines appended after attach are published
(client replays cover history)") only holds for clients that connect
*after* the run already exists — their own `stream`'s `each_entry` replay
covers it. It does **not** hold for a client that is already parked in
`pop_loop` (idle-state hello, `run: nil`) when the very first run (or a
post-prune-recovery run) appears: that client's own replay already ran
(over nothing), and it now depends entirely on the tailer to deliver the
new run — but the tailer, by design, delivers nothing for content that
existed at attach time. Concretely, on the empty-state UI itself the
copy invites exactly this sequence: *"Run `spm-cache build` to produce
the first run log."* — a user who opens the dashboard first and then
starts a build never sees the card populate, never sees a switch notice,
and the log viewport shows only whatever body lines happen to be
appended *after* the tailer's first tick, underneath the still-present
"No runs yet" empty-state markup (never cleared, since no
`resetForRun`/`buildCard`-triggering event ever arrives). This is not
tested anywhere in the phase's specs — `events_tailer_spec.rb`'s
"discovery, switch, and retention interplay" tests all write the first
run *before* starting the tailer/registering a client, so the client's
own `each_entry` replay always covers it, and no test exercises "client
already parked in idle hello, then the first run appears".

A second, narrower consequence of the same asymmetry: because
`from_byte0: false` computes the skip-offset *at the tailer's own first
tick* rather than at any particular client's connect time, any bytes
appended between an early client's own replay cutoff and the tailer's
first tick are **silently dropped by both mechanisms** — the client's
replay already finished before those bytes landed, and the tailer's
first attach treats everything present at its own tick as
already-covered. This breaks the "exactly-once replay→queue handoff"
guarantee the file otherwise implements carefully (the `(file, offset)`
composite-id suppression in `pop_loop` was built precisely to make this
handoff exact) — it just doesn't fire in this one path because no
`Entry` is ever queued for that range in the first place.

**Fix:** Make the nil-path attach symmetric with `switch_to`: replay
from byte 0 and publish an event, e.g.
```ruby
def discover
  newest = Dir.glob(File.join(@config.runs_dir, '*.jsonl')).sort.last
  return unless newest

  if @path.nil?
    attach(newest, from_byte0: true)
    @broadcaster.publish_switch(run: File.basename(newest), previous: nil)
  elsif newest > @path
    switch_to(newest)
  end
end
```
This is safe to do unconditionally: the existing exactly-once dedup in
`pop_loop` (`next if last_file && ([item.file, item.offset] <=> [last_file, last_offset]) <= 0`)
already suppresses these now-published entries for any client whose own
replay already covered that range, so clients that connected after the
run existed see no duplicates — only the previously-idle client (whose
`last_file` is `nil`, so the guard never fires) newly receives what it
was missing. `previous: nil` on the `Switch` payload is already handled
correctly on both ends: `pop_loop`'s `next if item.run == last_file`
still guards existing viewers, and `log.js`'s `renderSwitchNotice`
already no-ops when `previousRun` is falsy ("No previously-displayed run
→ no notice at all").

**Resolution:** Fixed. `Tailer#discover`'s nil-path attach is now
symmetric with `switch_to`: `attach(newest, from_byte0: true)` followed
by `@broadcaster.publish_switch(run: File.basename(newest), previous:
nil)`, exactly as proposed. TDD: `spec/events_tailer_spec.rb` gained a
RED spec ("delivers switch + replay to an already-parked idle client
when the first run appears (CR-02)") proving the gap via a real
`events.stream(client)` idle-hello connection, confirmed failing against
the pre-fix source, then the fix landed it GREEN. Most of that file's
other tests register a client directly against the tailer's own queue
(no per-connection replay to absorb the now-published Switch + one Entry
per already-on-disk line at first attach the way `Events#stream`'s
exactly-once dedup does), so they were updated via a shared
`drain_first_attach!` helper to drain that settle before asserting on
post-attach appends -- the underlying behavior change, not a weakened
assertion. `web_events_route_spec.rb` and `web_integration_spec.rb` are
unaffected: every client there goes through `Events#stream`, whose own
replay already covers the range and `pop_loop`'s dedup suppresses the
tailer's redundant publish.
**Commit:** `e5c45e5` (RED) -- `test(14-events): CR-02 failing spec for idle-client first-run replay (RED)`; `47ff8ff` (GREEN) -- `fix(14-events): CR-02 symmetric first-attach replay + switch notice (GREEN)`

## Warnings

### WR-01: Unhandled `Errno::ENOENT` in the pinned-fallback's own fallback replay can escape into WEBrick's handler

**File:** `lib/spm_cache/web/events.rb:246-263` (`Events#stream`)
**Issue:** When a pinned run (`?run=`) vanishes mid-flight during its own
replay, the rescue path delivers the pruned notice and falls back to
`fresh_run`, then replays *that* file:
```ruby
rescue Errno::ENOENT
  deliver_notice(client, PRUNED_NOTICE)
  follow = nil
  fresh = fresh_run
  if fresh
    last_file = fresh[:name]
    last_offset = fresh[:offset]
    self.class.each_entry(fresh[:path], fresh[:offset]) do |entry|   # <-- unguarded
      ...
    end
  end
end
```
This second `each_entry` call is not wrapped in its own rescue. If the
*fallback* file also vanishes between `fresh_run`'s derivation and this
`File.open` (the exact same retention race the surrounding code is built
to tolerate, just one level deeper), the resulting `Errno::ENOENT`
propagates out of the `rescue Errno::ENOENT` block itself — and is *not*
caught by `stream`'s own method-level `rescue Errno::EPIPE,
Errno::ECONNRESET, IOError` (`ENOENT` is none of those). The exception
then escapes the WEBrick body proc entirely, hitting WEBrick's generic
handler, which — per this codebase's own stated posture elsewhere
("the generic handler logs raises at ERROR level, and the terminal must
stay quiet", `router.rb`) — is exactly the noisy-terminal outcome this
phase otherwise takes care to avoid for retention races. The `ensure`
block still runs (client gets unregistered, no resource leak), so this
is a robustness/quiet-terminal gap rather than a crash or leak.

**Fix:** Wrap the fallback replay in the same defensive shape used
everywhere else in this method:
```ruby
if fresh
  last_file = fresh[:name]
  last_offset = fresh[:offset]
  begin
    self.class.each_entry(fresh[:path], fresh[:offset]) do |entry|
      client.write(self.class.frame(event: 'entry', data: entry.line, id: entry.id))
      last_file = entry.file
      last_offset = entry.offset
    end
  rescue Errno::ENOENT
    nil # doubly-pruned: the client already has the first notice; pop_loop's tailer-driven follow recovers
  end
end
```

**Resolution:** Fixed. Wrapped the fallback replay's `each_entry` call
in its own `begin/rescue Errno::ENOENT; nil; end`, mirroring the exact
defensive shape already used (and spec-verified) one level up in the
same method for the identical `each_entry`/`ENOENT` primitive. Verified
via an isolated probe exercising the fixed shape against a real
missing-file path (the rescue catches it, no exception propagates) plus
a full events-spec regression pass (83 examples green; this path is not
exercised by any existing spec). No dedicated hermetic regression test
was added: deterministically reproducing the specific doubly-narrow race
(the fallback file vanishing between `fresh_run`'s derivation and
`each_entry`'s own `File.open`, with no synchronization hook available
in that gap) would require either a flaky timing-dependent background
thread or stubbing `self.class.each_entry`/`fresh_run`, both foreign to
this file's real-objects-only, real-race testing convention.
**Commit:** `e59a158` -- `fix(14-events): W-01 rescue the doubly-pruned fallback replay in #stream`

## Info

### IN-01: `resetForRun`'s second parameter is called with three inconsistent argument shapes

**File:** `lib/spm_cache/web/assets/log.js:618,659,698`
**Issue:** `resetForRun(name, followOn)` treats its second argument as a
boolean (`follow = !!followOn`), but call sites pass three different
shapes: `resetForRun(payload.run)` (omitted → `undefined`),
`resetForRun(data.run, { followOn: true })` (an object literal, whose
truthiness happens to coerce to `true` regardless of its contents), and
`resetForRun(name, false)` (a real boolean). The object-literal call site
works only by accident of JS truthiness (any non-null object is truthy,
so `{ followOn: false }` would also evaluate to "follow on"); it reads
like a named-options call but isn't one.
**Fix:** Pass a plain boolean at every call site, e.g.
`resetForRun(data.run, true)` at line 659, for a single consistent
calling convention.

**Resolution:** Fixed. All three call sites now pass a plain boolean
(`resetForRun(payload.run, false)`, `resetForRun(data.run, true)`,
`resetForRun(name, false)` unchanged) -- no semantic change, since
`!!undefined`/`!!{...}` coerce identically to the explicit
`false`/`true` now written. Two `spec/web_frontend_spec.rb` examples pin
the auto-switch call site's literal source text; their regexes were
updated to the normalized shape alongside the source (123 examples
green).
**Commit:** `3fd9097` -- `fix(14-log-js): IN-01 normalize resetForRun follow-arg to a plain boolean`

### IN-02: `pid_alive?` is duplicated verbatim across two files

**File:** `lib/spm_cache/web/read_models/runs.rb:181-187`, `lib/spm_cache/core/run_log.rb` (`protected_run?`'s helper)
**Issue:** Both files implement the identical
`Process.kill(0, pid) rescue Errno::ESRCH => false rescue StandardError => true`
liveness probe independently. Not a bug (the comments even cross-reference
each other's line numbers), but it's a maintenance duplication: a future
change to the liveness semantics in one place is easy to forget in the
other.
**Fix:** Optional — extract to a shared `Core::` helper (e.g.
`Core::Process.alive?(pid)`) consumed by both `RunLog#protected_run?` and
`ReadModels::Runs.pid_alive?`. Low priority; not required for this phase.

**Resolution:** Left documented, not fixed. Explicitly optional/low
priority per this finding's own Fix note ("not required for this
phase"), and extracting a shared `Core::` helper would touch two files
beyond anything named in CR-01/CR-02/W-01 -- a refactor outside this
fix pass's scope, not a trivially-safe single-call-site change.

---

_Reviewed: 2026-09-01_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
