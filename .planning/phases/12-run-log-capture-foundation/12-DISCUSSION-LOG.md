# Phase 12: Run-Log Capture Foundation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-31
**Phase:** 12-Run-Log Capture Foundation
**Areas discussed:** --log-dir fate, Capture granularity, Retention policy, Which commands log

---

## --log-dir fate

| Option | Description | Selected |
|--------|-------------|----------|
| Repurpose (Recommended) | Existing flag becomes the run-log dir override with a project-relative default; matches dbt/glog default+override convention; makes the dead knob real; no second flag | ✓ |
| Remove the flag | Delete --log-dir; run logs always go to the default dir; YAGNI-clean but removes shipped CLI surface | |
| New --runs-dir flag | New flag with clear semantics; --log-dir removed anyway; two naming migrations | |

**User's choice:** Repurpose (Recommended)
**Notes:** Follow-up — default location:

| Option | Description | Selected |
|--------|-------------|----------|
| .spm-cache/runs/ (Recommended) | Project root, dotted — sibling of `.spm-cache-build.lock`; outside the sandbox; needs gitignore entry | ✓ |
| spm-cache-logs/ | Visible non-dotted dir; more discoverable, more clutter | |
| You decide | Planner picks under outside-sandbox + gitignored constraints | |

**User's choice:** .spm-cache/runs/ (Recommended)

---

## Capture granularity

| Option | Description | Selected |
|--------|-------------|----------|
| Events + lines (Recommended) | JSONL body carries stream-tagged terminal-parity lines AND structured events (run_start, package_start/end, phase markers, run_end); Phase 14 anchors become trivial lookups; MSBuild-binlog precedent; contract fixed now | ✓ |
| Parity lines only | Only what the terminal showed; Phase 14 parses package boundaries out of xcodebuild text later; smaller contract today, fragile text-parsing debt tomorrow | |

**User's choice:** Events + lines (Recommended)
**Notes:** Follow-up — huge builds:

| Option | Description | Selected |
|--------|-------------|----------|
| Full fidelity (Recommended) | Never truncate a run (SC2 reconstruct-the-run); disk bounded by size-aware retention | ✓ |
| Cap with truncation | Cap each run file (~10MB) keeping head+tail with truncation marker; bounded per-run size but the middle of the biggest logs is lost | |

**User's choice:** Full fidelity (Recommended)

---

## Retention policy

| Option | Description | Selected |
|--------|-------------|----------|
| Count + size (Recommended) | Keep last N runs AND prune oldest until total dir fits a size budget; standard rotation practice; count gives predictable replay history, size bounds the full-fidelity worst case | ✓ |
| Count only | Keep last N runs, ignore total size; worst case GBs after a release-build streak | |
| Age only | Delete runs older than X days; history varies with activity | |

**User's choice:** Count + size (Recommended)
**Notes:** Defaults and cleanup trigger:

| Question | Options | Selected |
|----------|---------|----------|
| Default values (configurable in spm-cache.yml) | 50 runs / 500MB · 20/200MB · 100/1GB | 50 runs / 500MB |
| When cleanup runs | At run start (rotation-time) · Explicit command | At run start |

---

## Which commands log

| Option | Description | Selected |
|--------|-------------|----------|
| All commands (Recommended) | Tee at Main.run catches every verb; one seam, no allowlist to maintain; full audit trail; retention caps noise; `web` excluded by design | ✓ |
| Heavy three only | Allowlist build/use/watch (LOGS-01's literal three); least noise; allowlist drift; rollback/remote invisible | |
| Three + rollback | build/use/watch + the destructive verb; still an allowlist | |

**User's choice:** All commands (Recommended)
**Notes:** Follow-ups:

| Question | Options | Selected |
|----------|---------|----------|
| Watch daemon mapping | Per-cycle files (each regen = own run file) · One rolling session file | Per-cycle files |
| Disable escape hatch | --no-run-log flag (matches --no-merge-slices precedent) · No flag | --no-run-log flag |

---

## Claude's Discretion

- Run-log file naming scheme (timestamp vs sequence) — left to planner
- Exact JSONL field names within the locked event vocabulary
- Additional internal phase markers beyond the minimum event set

## Deferred Ideas

None — discussion stayed within phase scope.
