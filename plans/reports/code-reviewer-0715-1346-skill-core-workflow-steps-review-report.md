# Code Review: SKILL.md Core Workflow (steps 1-5)

## Scope
- File: `skills/spm-cache/SKILL.md` (Core Workflow section, steps 1-5 replacing old 1-4)
- Type: agent-facing instructional documentation, no application code changed
- Cross-referenced: `lib/spm_cache/installer.rb`, `lib/spm_cache/core/config.rb`,
  `lib/spm_cache/command/{build,off,pkg/build,use,rollback,cache/list}.rb`,
  `lib/spm_cache/spm/pkg/proxy.rb`, `lib/spm_cache/spm/pkg/proxy_executable.rb`,
  `lib/spm_cache/assets/templates/spm-cache.yml.template`,
  `skills/spm-cache/references/troubleshooting.md`

## Score: 8/10

## Acceptance criteria check

**(1) Step 1 "Analyze project dependencies"** — Correct. `find . -name Package.resolved` matches
the same discovery mechanism as `Installer#generate_lockfile_from_resolved`
(`installer.rb:82`, `Dir.glob(File.join(@project_path, "**/Package.resolved"))`). Verified.

**(2) Step 2 "Ask which packages should not be cached" → `ignore` key only** — Correct, file writes
only to `ignore:`, never touches `cache_only`. Matches explicit user decision.

**(3) Step 3 batching (>5 packages, integrate+verify every batch)** — Correct as written. The
≤5 path and >5 batching-with-integrate-every-round are both present and match the described
design; `spm-cache build [TARGETS]` accepts space-separated positional args
(`argv.arguments!` in `command/build.rb:16` — CLAide collects all remaining args into an array,
confirmed this supports N space-separated names, not just internal array construction).

**(b) Renumbering / no stale references** — Clean. Old step 3 → 4 ("Verify cache status"), old
step 4 → 5 ("Rollback"). Grepped the whole file and `references/troubleshooting.md` for
`step [0-9]` / numeric step mentions — all remaining references (`step 1`, `step 2`, `step 3`)
are the new internal ones and are self-consistent forward-references. No section elsewhere
(Quick Command Reference, Configuration, SDK Options, Architecture) mentions step numbers at all,
so there was nothing to break.

**(c) CLI syntax validity** —
- `spm-cache build PkgA PkgB PkgC PkgD PkgE`: valid, confirmed via `command/build.rb`.
- `spm-cache pkg build TARGET --sdk=all`: valid, single positional arg (`argv.arguments!.first`),
  matches doc usage (doc never passes multiple targets to `pkg build`, only to `build`). Correct.
- `spm-cache cache list`: valid, `command/cache/list.rb` exists as advertised.
- `spm-cache off TARGETS`: valid, unchanged from doc, unaffected by this diff.
- `spm-cache` bare / `spm-cache build --recursive` / `--config=release`: all pre-existing options,
  present in `command/build.rb` (`BaseOptions`) — unaffected, still accurate.

**(d) Tone/format consistency** — Matches existing patterns: "tell the user X" imperative phrasing
(`SKILL.md:19` pre-existing, `:55` new — consistent), quoted verbatim question format for step 2,
bash blocks with trailing `#` inline comments consistent with rest of file and with
`troubleshooting.md`'s newly added `cache_only` paragraph (same "wins outright... skipped entirely"
phrasing reused verbatim in both places — good, avoids drift between the two docs).

**(e) Step 2 "create the file from the template if it doesn't exist yet" — MISLEADING, see High
Priority below.**

## Critical Issues
None.

## High Priority

**Step 2's manual "create the file from the template" instruction is redundant and points the
agent at machinery it can't reach.**

`ensure_config_file` (`installer.rb:57-64`) already auto-copies
`lib/spm_cache/assets/templates/spm-cache.yml.template` into the project root the moment *any*
`spm-cache` command that goes through `Installer#perform_install` runs (`build`, `use`,
`rollback`). Verified the template's defaults are identical to `Config::DEFAULT_CONFIG`.

The problem: step 2 tells the agent to do this manually **before** step 3 (the first real
`spm-cache` invocation), i.e. before the auto-creation would ever fire. But the template file the
instruction points to lives inside the installed gem
(`lib/spm_cache/assets/templates/spm-cache.yml.template`), at a path the agent has no way to
discover from the project directory — it's not exposed by any CLI command, and there's no `spm-cache
init`/`config init` equivalent. An agent following this instruction literally will either:
1. Search the filesystem for a gem it doesn't know the install location of, or
2. Fabricate a YAML file's contents from memory of the doc's example, risking omitting keys
   (e.g. `cache_only` is in `DEFAULT_CONFIG`/`Config#load` merge but is *not* in the actual
   template file on disk — a real, pre-existing drift between `DEFAULT_CONFIG` and the shipped
   template that this instruction would cause the agent to reproduce inconsistently).

Because `Config#load` merges any partial YAML with `DEFAULT_CONFIG` (`config.rb:51`), the correct
and simpler instruction is: just write a minimal file containing only the `ignore:` key (or none at
all if skipping) — no template lookup needed, and the first `spm-cache` invocation will fill in the
rest via `ensure_config_file` on next read regardless. As written, the doc invites unnecessary and
potentially incorrect agent behavior for zero functional gain.

**Fix**: replace "(create the file from the template if it doesn't exist yet...)" with something
like "(if `spm-cache.yml` doesn't exist yet, just write a file containing the `ignore:` key below —
`spm-cache` will fill in the remaining defaults on first run)".

## Medium Priority
None beyond the above.

## Low Priority (non-blocking)

`cat path/to/Package.resolved | grep '"identity"'` (step 1) — reasoned about typical SPM v2
`Package.resolved` schema (no fixture in `spec/` to check against directly): each pin is a JSON
object with `"identity" : "name"` on its own line under default `JSON.pretty_generate`/Xcode
formatting, so grep output is one clean `"identity" : "alamofire",` line per package — not the
noisy multi-line fragments a stricter regex extraction would risk. Since this is agent-facing
guidance (Claude reads and interprets the raw grep output, not a shell script doing string
splitting), the residual JSON punctuation is a non-issue for an LLM reader. Not worth blocking on,
but if this file is ever consumed by a non-LLM script, `grep -o '"identity" *: *"[^"]*"'` would be
the more defensible version.

## Side Effects Flagged
- None on application code — this is a documentation-only diff, verified no `.rb`/`.swift` files
  were touched as part of the reviewed sections (unrelated files under `lib/` and `tools/` show
  modifications in `git status` from other work, but are out of scope for this diff and were not
  reviewed here).
- The step-2 instruction (High Priority item) is a behavioral side effect risk for the *agent*,
  not the codebase: if followed literally it could cause the agent to burn turns searching for an
  internal gem asset path, or to hand-author a config file that omits `cache_only` and other keys
  the real template doesn't even define, creating a false sense of parity with `ensure_config_file`.

## Recommended Actions
1. (High) Reword step 2's parenthetical to remove the "copy from template" instruction; rely on
   `Config#load`'s merge-with-defaults behavior instead.
2. (Low, optional) Tighten the `grep '"identity"'` command to `grep -o` with a capture if this file
   is ever expected to feed a non-LLM parser.

## Unresolved Questions
- None — all three explicit user decisions (step 1 discovery mechanism, `ignore`-only in step 2,
  batch-integrate-every-round in step 3) are confirmed correct against the Ruby implementation and
  are not being re-litigated here.
