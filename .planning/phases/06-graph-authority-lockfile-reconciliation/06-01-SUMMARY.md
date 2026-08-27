---
phase: 06-graph-authority-lockfile-reconciliation
plan: 01
subsystem: measurement
tags: [m1, attribution, package-resolved, locator, lockfile, field-evidence]
status: complete

requires: []
provides:
  - "M1 attribution verdict (H-wrongfile 25 / H-lock 0 / H-float 0 / both 0) that Phase 7's design lock depends on"
  - "Dated field evidence of the two-candidate Package.resolved finding and the main-branch zero-overlap finding (D-12)"
  - "Measured justification for promoting candidate disambiguation into Phase 6 / FID-01 as blocking"
affects:
  - "Phase 6 Plan 02+ — reconciliation must not run against find_package_resolved's current answer"
  - "Phase 7 — re-scoped from primary fix to hardening (D-14)"
  - "DIAG-01 — set-membership requirement confirmed by measurement"

tech-stack:
  added: []
  patterns:
    - "Attribution keyed with DiffDetector#identity_key / #normalize_url rather than raw URL strings"
    - "Read-only cross-branch inspection via git show <rev>:<path> instead of checkout, when the working tree is dirty"

key-files:
  created:
    - .planning/phases/06-graph-authority-lockfile-reconciliation/06-M1-MEASUREMENT.md
  modified:
    - .planning/STATE.md

key-decisions:
  - "Dominant mechanism is H-wrongfile: the locator's Dir.glob(...).find returns a nested git-ignored 2026-07-12 Package.resolved (8 pins) instead of the canonical 2026-08-13 file (17 pins), because S (0x53) sorts before p (0x70)"
  - "H-float excluded by construction: all 8 built packages were emitted as exact revision: pins, which have no range to float within, and U == L byte-for-byte"
  - "H-lock excluded by provenance: the lock matches the wrongly-picked file 8/8 and the canonical file 0/17, and no committed revision of the canonical file ever held the pins the lock carries"
  - "Candidate disambiguation promoted into Phase 6 / FID-01 as blocking — reconciling against the currently-picked file writes the phantom graph back onto itself and turns success criterion 1 into a false green"
  - "Phase 7 proceeds (D-14) but is demoted from primary fix to hardening against a mechanism M1 did not observe in the field"
  - "Live Release build withheld deliberately: A3 failed, and the only probative commit is reachable solely via detached checkout in a dirty tree whose build would overwrite the pre-fix artifacts"

requirements-completed: []
requirements-evidenced: [FID-01, FID-06]
requirements-note: >
  The plan frontmatter lists FID-01 and FID-06, but this plan wrote no source and completes
  NEITHER. FID-01 (reconcile version/revision on every non-fast-path run) and FID-06 (canonical
  locator preference) are both implementation requirements delivered in later Phase 6 plans; both
  remain Pending in REQUIREMENTS.md. What this plan delivers is the M1 measurement obligation —
  the evidence that makes FID-06 blocking rather than optional. Marking them complete here would
  assert the locator fix had shipped while the defect is still live, which is the exact false-green
  failure mode this measurement exists to prevent.

coverage:
  tests-added: 0
  suite: "258 examples, 0 failures (baseline unchanged — this plan touched no source)"

metrics:
  duration: ~35m
  completed: 2026-08-27
  tasks: 2
  commits: 2

actuals:
  tokens: 31000
  tasks: 2
  commits: 2
---

# Phase 6 Plan 01: M1 Root-Cause Reproduction & Falsifiable Attribution Summary

Attributed the motivating stale-transitive release build to **H-wrongfile** for all 25 packages
(H-lock 0, H-float 0, both 0), proving by provenance and by exact-commit emission that the lockfile
chain and version floating are both excluded — the locator reads a nested git-ignored `Package.resolved`
frozen at 2026-07-12 while Xcode's real graph moved twice.

## What Was Built

No code. Two documentation artifacts carrying the measurement Phase 7's design is locked against:

- `06-M1-MEASUREMENT.md` — candidate inventory, live `DiffDetector` verdict, per-candidate set
  arithmetic, umbrella emission and realization, a 25-row per-package attribution table, applied
  falsifiers, the A3 failure record, the release-build section, and the verdict.
- `.planning/STATE.md` — one appended dated `[Phase 06 — M1, 2026-08-27]` decision (D-13).

## M1 Verdict (restated inline per D-13)

**Dominant mechanism: H-wrongfile. Counts — H-wrongfile 25 · H-lock 0 · H-float 0 · both 0.**

`Dir.glob(File.join(project, "**/Package.resolved")).find { |f| File.exist?(f) }` returns the nested
`StressMonitor.xcodeproj/StressMonitor.xcodeproj/…` copy (2026-07-12, 8 pins) rather than the canonical
`StressMonitor.xcodeproj/project.xcworkspace/…` file Xcode maintains (2026-08-13, 17 pins), because
`S` (0x53) sorts before `p` (0x70). The nested directory is git-ignored build junk
(`.gitignore:171`), so Xcode never updates it and no clean step removes it.

Every downstream component then agreed with every other — lock entry, emitted umbrella requirement,
umbrella resolved pin, and realized checkout HEAD are byte-identical for all 8 built packages — while
collectively describing a graph the host project does not have.

Set arithmetic (keyed by `DiffDetector#identity_key`): lock ∩ picked file = **8/8**;
lock ∩ canonical file = **0/17**. That pair of numbers is what decides between H-lock and H-wrongfile.

### Symptom reproduced

Four packages linked strictly older than their contemporaneous host pin, verified against realized
checkout HEADs under `umbrella/.build/checkouts` (the sources the compiler actually read):

| package | linked | host pin (@`0a73df7`, 2026-08-09) |
|---|---|---|
| AnchoredPopup | 1.1.3 / `2fb9d1ac101b` | 1.2.1 / `dfa61fd6e4e4` |
| Kingfisher | 8.8.1 / `c152c1915f60` | 8.11.0 / `410984bf301f` |
| libwebp-Xcode | 1.5.0 / `0d60654eeefd` | 1.6.0 / `2b5256c29ff4` |
| MediaPicker | 3.3.2 / `ce2eda630033` | 3.4.2 / `07fa01cdf084` |

The other 17 packages of the real host graph were never declared by the umbrella at all.

### Falsifiers that settled it

- **H-float refuted for all 8** — every package emitted as an exact `revision:` pin, which per
  `Lockfile.swift:115-117` has no range to float within, and `U == L` byte-for-byte. Concretely for
  Kingfisher: emitted, lock, umbrella pin, and on-disk checkout HEAD are all `c152c1915f60`.
- **H-lock refuted by provenance** — the lock holds AnchoredPopup `1.1.3 / 2fb9d1ac101b`, identical to
  the nested file, while the host's own graph held `1.2.1 / dfa61fd6e4e4` the same day. No committed
  revision of the canonical file ever held `1.1.3`, so the lock is not a frozen read of the host graph.
- **H-lock refuted for the 17 by absence** — across 12 commits of the canonical file (2026-03-08 →
  2026-08-13) the lock never held a firebase-graph pin at any version. There is no stale state to
  unfreeze; the mechanism is invisibility.

## Deviations from Plan

### A3 — assumption failed (recorded, not improvised around)

`feature/spm-cache-integration`'s tip no longer holds the ExyteChat/MediaPicker state that D-11 assumed.
`fb8e773` ("remove unused ExyteChat/SwiftUICharts proxy dependencies", 2026-08-10) is an ancestor of the
tip `a56a90d`, and it also removed the canonical `Package.resolved` from git tracking. The state survives
only at ancestor commits `1b511d1` / `0a73df7` (both 2026-08-09) — precisely the era `spm-cache.lock` was
written (mtime 2026-08-09 21:46).

**Impact: none on attribution.** The attribution rests on committed artifacts, read via
`git show <rev>:<path>`, not on a working-tree state. Assumption A4 held — the scheme is `StressMonitor`.

### Live Release build withheld (deliberate, per plan escape hatch)

Neither reachable variant of the `xcodebuild` command is both probative and non-destructive:

- The current tree (`main`) has an **empty** `XCLocalSwiftPackageReference` section — spm-cache is not
  wired in and no exyte package is present, so a build there is non-probative.
- The probative commit `1b511d1` is reachable only by detached checkout in a reference tree carrying 3
  modified tracked files and `stash@{0}`, **and** a build there regenerates `spm-cache.lock`,
  `umbrella/Package.swift`, and `umbrella/Package.resolved` — the three pre-fix artifacts this plan
  exists to capture.

Version attribution was instead established from realized checkout HEADs, which is stronger evidence
than a build log for this purpose. ROADMAP success criterion 4 is satisfied: the symptom reproduced and
every package is attributed.

### Requirement completion withheld (Rule 1 — self-corrected)

The plan frontmatter lists `requirements: [FID-01, FID-06]`, and the state-update step marked both
Complete in `REQUIREMENTS.md`. **That was reverted.** Both are implementation requirements — FID-01 is
the reconciliation itself, FID-06 is the canonical-locator preference — and this plan wrote no source.
Leaving them checked would have told the Phase 6 verifier that the locator defect was fixed while it is
still live, which is the same false-green pathology the measurement itself warns about in consequence 1.
Both are back to `Pending`; `REQUIREMENTS.md` is unmodified by this plan.

### Path correction found mid-measurement

The reference git repo root is `/Users/…/ios-stress-app`, one level **above** the `StressMonitor`
project directory. An initial A3 check run from the subdirectory returned a misleading empty result
because git applies a path prefix when invoked from a subdirectory. All git inspection was redone from
the repo root; the measurement file records paths relative to it explicitly so a later reader cannot
repeat the mistake.

## Threat Mitigations Applied

- **T-06-11 (tampering with the reference tree)** — `git status --porcelain` and `git stash list`
  recorded before any command ran; `spm-cache.lock` copied to a scratch path first. **No branch switch,
  no build, no commit** in the reference project. Verified afterward: the lock is byte-identical to the
  preserved copy, all five artifact mtimes are unchanged, and the tree is still on `main` with its
  original dirty state.
- **T-06-12 (information disclosure)** — only package identities, versions, revisions, and repo-relative
  paths recorded. No build log pasted; no signing identities, team IDs, or provisioning UUIDs.
- **T-06-13 (repudiation)** — every verdict cell is recomputable from the printed H/L/U triple in the
  same table. The per-package linked-version transcription was independently re-derived
  programmatically from `git rev-parse HEAD` / `describe --tags` on each checkout and matched row for
  row, which discharges the plan's `<human-check>`.

## Verification

| Gate | Result |
|---|---|
| All six required headings + Step 4 placeholder lifecycle | PASS |
| `git diff --name-only HEAD -- lib spec tools` | **empty** — no source touched |
| `.planning/STATE.md` append-only | PASS — 1 insertion, 0 deletions, exactly 1 new bullet |
| `bundle exec rspec` | **258 examples, 0 failures** (baseline unchanged) |
| Per-package linked versions re-derived from source data | PASS — matches Step 4 table exactly |

## Known Stubs

None.

## Commits

| Commit | Description |
|---|---|
| `11dfc3b` | M1 candidate inventory, DiffDetector verdict, per-package attribution |
| `0cfcd4b` | Release-build reproduction, M1 verdict, dated STATE.md decision |

## Follow-On Consequences

1. **Blocking for Phase 6 Plan 02+** — reconciliation must not use `find_package_resolved`'s current
   answer. Candidate disambiguation belongs in FID-01, or success criterion 1 becomes a false green.
2. **Phase 7 re-scoped** (D-14) — proceeds, but as hardening against the `from:` drift mechanism, which
   M1 observed **zero** times in the field. It would not have prevented the motivating failure.
3. **DIAG-01 confirmed** — a version-only check over the intersection reports "0 drifted" on a lock
   sharing zero packages with the host graph. Set membership is required, as CONTEXT.md specified.

## Self-Check: PASSED

- `06-M1-MEASUREMENT.md` — FOUND
- `.planning/STATE.md` — FOUND, contains `[Phase 06 — M1, 2026-08-27]`
- Commit `11dfc3b` — FOUND
- Commit `0cfcd4b` — FOUND
