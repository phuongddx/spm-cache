---
phase: 16-package-toggles-panel-completion
plan: 01
subsystem: core
tags: [config, mutator, flock, atomic-write, toggle, tracer]

requires:
  - phase: 15-ui-build-controls
    provides: "Web::Jobs slot + fake-bin fixture; Router dispatch/gate shapes; the ONE-boot integration spec"
provides:
  - "Config#set_ignored_all / #set_ignored — the shared mutator: blocking flock on the inode-stable SIDECAR <config_path>.lock, fresh in-lock re-read (reset!+load), key-level ASSIGN, atomic tmp+rename save, release in ensure; silent by contract"
  - "Config#save upgraded IN PLACE — same-dir Tempfile + File.rename, existing mode preserved (chmod before rename), new files 0644, bytes identical to the old File.write shape"
  - "Config.configure re-derives config_path from project_dir (explicit config_path still wins); Config#config_lock_path"
  - "POST /api/toggle tracer arm — token → verb-404 → bad_body/bad_package/bad_cached → mutator → ok envelope {package, cached}; never references @jobs (D-08)"
  - "/api/state rows: saved_cached / applied_cached / pending from a FRESH per-call disk parse of the ignore list (missing/malformed → empty list)"
  - "`spm-cache off` routed through the same mutator with its published contract pinned byte-for-byte"
affects: [16-02, 16-03, 16-04, 16-05, 16-06]

actuals:
  tokens: 14700   # chars/4 over the realized lib+spec+.gitignore diff (58,753 bytes)
  tasks: 3
  commits: 6

key-decisions:
  - "applied_cached = nil for no-graph-entry rows, else (status != 'ignored') — the plan's action pins only those two cases; hit/missed/excluded/plugin all read as applied-cached in the tracer, and 16-03's reason matrix narrows pending to toggleable rows"
  - "In-lock reload is reset! + load, not bare load: a config DELETED mid-flight reads as defaults instead of resurrecting the boot snapshot (load alone keeps @raw when the file is absent)"
  - "The integration boot injects State's own cache_root seam via read_models: — /api/state rows were otherwise ambient (real ~/.spm-cache is machine-global); deterministic AND hermetic now"
  - "Tasks 2/3 were born-green (Task 1 landed the collaborator): RED proven by re-running against the pre-refactor tree (13 examples, 10 failures) and by drift-injection (off line drift fails the byte-exact rows)"
  - "Task 3 GREEN is an empty commit — zero production delta was the plan's expected outcome; the gate is recorded so the TDD pair exists"

requirements-completed: [TOGL-01]

coverage:
  - id: D1
    description: "TRACER: POST /api/toggle → shared mutator → locked atomic yml write → saved≠applied on /api/state"
    requirement: TOGL-01
    verification:
      - kind: integration
        ref: "spec/web_integration_spec.rb 'POST /api/toggle (16-01 tracer)' — 5 rows incl. the slot-held D-08 row"
        status: pass
      - kind: unit
        ref: "spec/config_mutator_spec.rb — 10 own rows: sidecar target, blocking defer, inode stability P5/P6, clobber P3, atomicity, purity, release-on-raise, path derivation"
        status: pass
      - kind: unit
        ref: "spec/command_off_shared_mutator_spec.rb — 6 D-03 byte-identical pins"
        status: pass
    human_judgment: false

duration: 50min
completed: 2026-09-02
status: complete
---

# Phase 16 / Plan 16-01: TRACER — one browser toggle, end to end

**An authenticated POST /api/toggle writes the ignore list through one shared Config mutator (sidecar flock → fresh in-lock re-read → key-level assign → atomic rename replace) that `spm-cache off` also uses; the next GET /api/state serves the row saved-not-cached while its graph status still says cached.**

## Task Commits
1. RED tracer rows + hermetic state boot — `98d63f4`
2. GREEN mutator + atomic save + toggle arm + state fields — `62dc106`
3. RED mutator matrix — `7b7c5d9`
4. GREEN .gitignore sidecar (zero hardening needed) — `86085d5`
5. RED off contract pins — `21f4f3d`
6. GREEN D-03 gate (empty — zero production delta, as planned) — `e38ff4d`

## Notes
- Scoped final snapshot: **132 examples, 0 failures** across web_integration + config_mutator + command_off_shared_mutator + config + web_state + web_build_routes. Suite baseline at start: 984/0.
- Tracer feedback gate re-run GREEN before expansion (autonomous run).
- Deviations: (Rule 3) spec/web_state_spec.rb touched though not in Task 1's files list — its strict full-row `eq` pins must carry the three beside-fields for the file to stay green (Task 1's verify requires it); extension only, no row weakened. (Rule 3) integration boot injects `read_models: { state: … }` with State's own `cache_root:` seam — without it the Alamofire/SnapKit rows depend on the developer's real ~/.spm-cache (non-deterministic, non-hermetic); production State.call unchanged.
- RED honesty for the born-green tasks: the mutator matrix was run against the pre-refactor config.rb (10/13 fail, the P3 clobber row loses `OtherWriter`); the off pins were drift-injected (2/6 fail). Both proven discriminative, then restored byte-identical.
- No flock on any yml inode anywhere in the tree; no `<<`/push/delete against `raw['ignore']` — the only writes are assignments.
- Sidecar `spm-cache.yml.lock` gitignored beside the yml entry (A2); the repo dogfoods itself.

## Files
- lib/spm_cache/core/config.rb (configure re-derivation, config_lock_path, set_ignored_all/set_ignored, atomic save)
- lib/spm_cache/command/off.rb (routed through the mutator; both puts lines untouched)
- lib/spm_cache/web/router.rb ('/api/toggle' arm + api_toggle)
- lib/spm_cache/web/read_models/state.rb (saved_ignore_list + saved_cached/applied_cached/pending)
- .gitignore (spm-cache.yml.lock)
- spec/config_mutator_spec.rb (new, 13 examples — 10 own rows), spec/command_off_shared_mutator_spec.rb (new, 9 examples — 6 own rows), spec/web_integration_spec.rb (+5 tracer rows), spec/web_state_spec.rb (strict-eq rows extended with the beside-fields)

## Deferred to the orchestrator / later plans
- Full-suite wave gate (`bundle exec rspec`) is the orchestrator's wave-1 gate by the execution constraint (sibling plan 16-02 runs concurrently); all of this plan's scoped verifies are green.
- The browser checkbox half is 16-05/16-06's; unknown_package / not_toggleable / config_write_failed / revert / apply are 16-04's; reason + toggleable derivation is 16-03's.

## Self-Check: PASSED
- Files found: spec/config_mutator_spec.rb, spec/command_off_shared_mutator_spec.rb, 16-01-SUMMARY.md
- Commits found on HEAD: 98d63f4, 62dc106, 7b7c5d9, 86085d5, 21f4f3d, e38ff4d
