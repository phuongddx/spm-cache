# Phase 6 — Deferred Items

Out-of-scope discoveries logged during execution. Not fixed in the plan that found them.

## `DiffDetector#live_packages` raises on a malformed host `Package.resolved`

**Found during:** Plan 03, Task 2 (the D-04 warn-and-degrade examples)
**File:** `lib/spm_cache/core/diff_detector.rb` lines 138-153

`live_packages` does an unguarded `JSON.parse(File.read(resolved))`. A truncated or non-object
`Package.resolved` therefore raises out of `Installer#detect_diff` and aborts the whole `use` run
*before* `reconcile_lockfile_from_host_graph`'s D-04 guard can warn and degrade. The reconciler's
guard is correct and covered by a named example, but for that one input shape it is unreachable in
the field.

**Suggested fix:** route the read through `Core::PackageResolved.pins_or_nil` and treat `nil` as
"no resolved pins — fall through to the pbxproj union", matching the tolerant posture every other
caller of the locator already takes.

**Why deferred:** `core/diff_detector.rb` is not in Plan 03's `files_modified`, the behavior is
pre-existing, and it is not caused by Plan 03's changes. Changing the detector's raise posture
alters what `use` does on a malformed host graph for every caller, which warrants its own decision.
