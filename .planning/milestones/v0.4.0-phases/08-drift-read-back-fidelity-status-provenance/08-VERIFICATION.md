---
phase: 08-drift-read-back-fidelity-status-provenance
verified: 2026-08-29T17:10:00Z
status: passed
score: 8/8 must-haves verified
behavior_unverified: 0
overrides_applied: 0
---

# Phase 08: Drift Read-Back, Fidelity Status & Provenance Verification Report

**Phase Goal:** Every cached artifact carries a verifiable record of the graph it was actually
built against, and any package whose realized versions differ from the intended pins is reported
instead of silently shipped — seeding without this is strictly worse than today.
**Verified:** 2026-08-29T17:10:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Drift between intended (host-seeded) and realized (post-build) pins is detected and reported, comparing against separately retained intended pins, never against the file spm-cache itself wrote (roadmap SC1) | ✓ VERIFIED | `build_pipeline.rb:68` captures `intended_pin_map` from `resolved_pins_file` immediately after `seed_host_graph` returns, before `perform_build` runs; `report_fidelity` (line 103) re-reads the realized side from `pkg_dir/Package.resolved` — a different file, read a second time, after the build. End-to-end test `spec/build_pipeline_provenance_spec.rb:47-94` stubs `xcodebuild` silently rewriting `Package.resolved` from `aaa111`→`bbb222` mid-build and asserts a `Core::UI.warn` naming both values on stderr. |
| 2 | A package whose declared requirements genuinely cannot satisfy the host graph builds from source with a distinct `resolution-incompatible` status; build succeeds, never hard-fails, `ignore_build_errors` cannot suppress/mask it (roadmap SC2) | ✓ VERIFIED | `report_fidelity` runs entirely on `run`'s success path (after `success = true`, before `result` is returned), never via `raise` — no `raise` statement anywhere in `report_fidelity`/`write_provenance_sidecar`. Regression test `spec/build_pipeline_provenance_spec.rb:709-724` stubs `Config#ignore_build_errors?` to raise if ever queried and confirms it is never queried on a successful resolution-incompatible run. |
| 3 | Each cached `.xcframework` has a provenance sidecar recording realized pins + spm-cache version + config + destination set; replacing a prebuilt binary-target artifact removes the stale sidecar (roadmap SC3) | ✓ VERIFIED | `write_provenance_sidecar` (`build_pipeline.rb:171-188`) writes exactly `{fidelity_status, pins, spm_cache_version, config, destinations}` via atomic tempfile-then-rename. `copy_prebuilt_binary_target` (line 1045) and the not-seeded branch of `report_fidelity` (line 99) both `FileUtils.rm_f` any stale sidecar. Verified via `spec/build_pipeline_provenance_spec.rb:47-94` (exact 5-key equality), `:376-410` (vendored/nil-host-graph cleanup), `:445-520` (Class E sidecar + destination-narrowing). |
| 4 | `spm-cache build` output and `cache list` name each package's fidelity status (`host-pinned`/`resolution-incompatible`/`not-graph-pinned`) — no package's resolution outcome is unauditable (roadmap SC4) | ✓ VERIFIED | `Core::UI.info` line printed inline in `report_fidelity` (build_pipeline.rb:115); `Command::Cache::List#run` (`lib/spm_cache/command/cache/list.rb:19-23`) reads `fidelity_status_for` per `*.xcframework` glob entry, falling back to `not-graph-pinned`. Verified via `spec/command_cache_list_spec.rb` (9 examples covering happy path, missing/malformed/keyless sidecars, TOCTOU race, sidecar-not-listed, multi-config sort, empty-cache header). |
| 5 | A vendored `.xcodeproj` package and a plain `spm-cache pkg build` invocation (no host graph) are completely unaffected — no new output, no sidecar (08-01 must_have) | ✓ VERIFIED | `seed_host_graph` returns `[nil, false]` for both cases; `report_fidelity`'s `unless seeded` branch only does `rm_f` (no-op when nothing exists) and returns, printing nothing. `command/pkg/build.rb`'s call site deliberately never passes `resolved_pins_file`, confirmed unmodified by this phase (`git log` shows no touch to that file). Verified via `spec/build_pipeline_provenance_spec.rb:376-410`. |
| 6 | `Installer::Build#build_single_target` threads `config:` into every `SPM::BuildPipeline.run` call (08-01 must_have) | ✓ VERIFIED | `lib/spm_cache/installer/build.rb:174` passes `config: @config_name` into the `SPM::BuildPipeline.run(...)` call. Verified via `spec/build_pipeline_provenance_spec.rb:552` (`hash_including(config: "debug")`). |
| 7 | Diff scoping is intersection-only (identities on only one side are never drift); nil/malformed inputs default safely to host-pinned; revision-over-version precedence honored (08-01 must_have) | ✓ VERIFIED | `drifted_identities` (build_pipeline.rb:128-134) computes strictly `intended.keys & realized.keys`; `pin_value_map`/`host_pin_value` (lines 141-156) mirror `Core::Diagnostics`'s revision-over-version precedence. Verified via `spec/build_pipeline_provenance_spec.rb:612-679` (5 dedicated edge-case examples). |
| 8 | `cache list`'s sidecar files never appear as their own spurious cached-package entry — pre-existing bug fixed (08-02 must_have) | ✓ VERIFIED | `Command::Cache::List#run` iterates `Dir.glob(cache_dir, "*.xcframework")` exclusively (never raw `Dir.entries`), so `.shims.json`/`.provenance.json` can never match the glob. Verified via `spec/command_cache_list_spec.rb:91-99`. |

**Score:** 8/8 truths verified (0 present, behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/spm_cache/spm/build_pipeline.rb` | drift read-back, resolution-incompatible classification, provenance sidecar write/cleanup, build-output status line | ✓ VERIFIED | `report_fidelity`, `drifted_identities`, `pin_value_map`/`host_pin_value`, `write_provenance_sidecar`, `actual_destinations_for`/`slice_satisfies?` all present and wired into `run`'s single consolidated insertion point (line 73) |
| `lib/spm_cache/installer/build.rb` | threads `config:` into every `SPM::BuildPipeline.run` call | ✓ VERIFIED | Line 174: `config: @config_name` |
| `spec/build_pipeline_provenance_spec.rb` | FID-03/FID-04/CACHE-01/DIAG-02 regression coverage (new file) | ✓ VERIFIED | 725 lines, 20 `it` blocks covering every scenario in both plans' `<behavior>` sections |
| `lib/spm_cache/command/cache/list.rb` | per-module fidelity status column; fixes sidecar-as-spurious-entry bug | ✓ VERIFIED | Rewritten to `Dir.glob("*.xcframework")` + `fidelity_status_for` |
| `spec/command_cache_list_spec.rb` | DIAG-02 cache-list regression coverage (new file) | ✓ VERIFIED | 133 lines, 9 `it` blocks |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `BuildPipeline.run` | `Core::PackageResolved.pins_or_nil(resolved_pins_file)` | intended pins captured before `perform_build` runs | ✓ WIRED | `build_pipeline.rb:68` — never re-derived from `pkg_dir/Package.resolved` post-build |
| `seed_host_graph`'s `seeded` boolean | both ensure-restore and provenance write/cleanup branches | single gate | ✓ WIRED | `run`'s `ensure` (line 77) and `report_fidelity`'s `unless seeded` (line 93) both keyed off the same `seeded` value |
| `copy_prebuilt_binary_target` (Class E) return value | `run`'s single consolidated insertion point | `perform_build`'s return flows through `run` uniformly | ✓ WIRED | `perform_build:229-230` returns `[output_path, actual_destinations_for(...)]`, same tuple shape as the other two paths (lines 306, 367) |
| `Installer::Build#build_single_target` | `SPM::BuildPipeline.run(..., config: @config_name)` | `command/pkg/build.rb` deliberately untouched | ✓ WIRED | `installer/build.rb:174`; confirmed `command/pkg/build.rb` has no `resolved_pins_file`/`config:` args added (out of scope, verified unmodified) |
| `BuildPipeline`'s sidecar path convention | `Command::Cache::List`'s sidecar lookup | identical `"#{fw_path}.provenance.json"` construction | ✓ WIRED | `build_pipeline.rb:172` (`"#{output_path}.provenance.json"`, `output_path = out_dir/<name>.xcframework`) matches `list.rb:21` (`"#{fw_path}.provenance.json"`, `fw_path` from `Dir.glob(cache_dir, "*.xcframework")`) exactly |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| FID-03 | 08-01 | Realized dependency versions read back and compared; drift reported | ✓ SATISFIED | `report_fidelity`/`drifted_identities`; `spec/build_pipeline_provenance_spec.rb:47-94` |
| FID-04 | 08-01 | Package that can't satisfy host graph falls back to source, distinct `resolution-incompatible` status, never hard-fail, never maskable | ✓ SATISFIED | Classification lives on success path only, never raised; `spec/build_pipeline_provenance_spec.rb:709-724` |
| CACHE-01 | 08-01 | Cached `.xcframework` records graph provenance (realized pins, version, config, destinations) | ✓ SATISFIED | `write_provenance_sidecar`; exact 5-key JSON verified |
| DIAG-02 | 08-01 (build-output half), 08-02 (cache-list half) | Per-package fidelity status surfaced in build output and `cache list` | ✓ SATISFIED | `Core::UI.info` status line + `Command::Cache::List` rewrite |

**Orphaned requirements check:** `REQUIREMENTS.md`'s Phase 8 row lists exactly FID-03, FID-04,
CACHE-01, DIAG-02 — identical to the union of both plans' `requirements:` frontmatter. No
orphans.

**Note (non-blocking):** `REQUIREMENTS.md`'s traceability table (lines 116-124) and
`ROADMAP.md`'s Phase 8 checkboxes still show `Pending`/`[ ]` for these four requirement IDs and
the phase itself, despite the code being complete and both SUMMARY.md files claiming
`status: complete`. This is a documentation-sync gap, not a code gap — flagged for whoever runs
the next `/gsd-progress` or ship step to update, not a blocker to this verification.

### Anti-Patterns Found

None. Scanned all 5 modified/created files (`build_pipeline.rb`, `installer/build.rb`,
`command/cache/list.rb`, and both new spec files) for `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/
`PLACEHOLDER` markers, alarming/error-style status wording, and empty/stub implementations.
Zero unreferenced debt markers found (one incidental match for the word "placeholder" at
`build_pipeline.rb:479` is prose describing Google's shim-target naming convention, not a debt
marker).

### Behavioral Spot-Checks / Test Execution

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| New provenance spec suite | `bundle exec rspec spec/build_pipeline_provenance_spec.rb spec/command_cache_list_spec.rb` | 29 examples, 0 failures | ✓ PASS |
| Full suite regression | `bundle exec rspec` | 368 examples, 0 failures | ✓ PASS |
| Commit provenance | `git log --oneline --all` for all 9 commits cited across both SUMMARY.md files | all present | ✓ PASS |

### Human Verification Required

None. All truths were verifiable via code inspection, wiring traces, and the actual passing test
suite (not a re-run of SUMMARY.md's claimed numbers — the full suite and targeted specs were
executed fresh in this verification pass).

### Gaps Summary

None. All 8 merged must-have truths (4 roadmap Success Criteria + 4 additional plan-level
must_haves not already covered by the roadmap wording) are verified true against the actual
codebase, all 4 requirement IDs are satisfied and none are orphaned, all prohibitions (no hard
fail, no false-positive drift, no raise-based classification, exactly 5 sidecar fields, no
alarming wording) hold, and the full 368-example test suite passes with zero failures. The two
carried-over Info-tier code-review findings (`IN-01`: redundant but harmless `rm_f` in
`copy_prebuilt_binary_target`; `IN-02`: `slice_satisfies?` duplicated across two files) were
explicitly and correctly scoped out of the fix pass as non-blocking per `08-REVIEW.md` — neither
affects goal achievement.

---

_Verified: 2026-08-29T17:10:00Z_
_Verifier: Claude (gsd-verifier)_
