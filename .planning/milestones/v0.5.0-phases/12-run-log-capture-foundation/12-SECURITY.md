---
phase: "12"
slug: "run-log-capture-foundation"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-09-01"
---

# Phase 12 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Terminal subprocess output → run log | xcodebuild/swift stdout+stderr text crosses from subprocess space into the persistent JSONL body via `Core::Sh` reader threads / StreamSink | Untrusted subprocess text (log-forging vector); no env or credential data |
| User argv / local config → run log | CLI flags and `spm-cache.yml` values (runs_dir, retention budgets) cross from same-user local input into file paths and run_start headers | Local same-trust input; argv may carry credential-bearing URLs (redacted in header) |
| Runs dir on local disk | `.spm-cache/runs/` persists for weeks (retention D-06) and could enter VCS or fill the disk | Log content (secrets if leaked, disk volume) |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-12-01 | Tampering (log-forging) | RunLog body lines / StreamSink / event name fields | medium | mitigate | `JSON.generate` escapes every body payload; body lines carry only ts/stream/text and never an `event` key; `sh` events carry escaped cmd + numeric status; emission-site comment pins Phase 14 renderers to key on `event` and treat text/name as data | closed |
| T-12-02 | Tampering (path traversal via --log-dir) | `RunLog.pre_scan` / runs_dir | low | accept | Same-user local input mirroring existing `--config`/project_dir handling; retention budget values Integer-coerced with rescue-to-default | closed (accepted) |
| T-12-03 | Tampering (symlink swap on runs dir) | `RunLog.open` / `RunLog#prune` | low | accept | Header published via same-dir Tempfile+rename; prune unlinks individual `*.jsonl` candidate names only — no rm_rf, no directory replacement; local project dir is same-trust | closed (accepted) |
| T-12-04 | DoS (disk-fill via log growth) | RunLog append path (incl. N watch cycle files) | high | mitigate | D-06/D-07 retention: count (`runs_keep`=50) AND size (`runs_max_mb`=500MB), oldest-first, pruned at EVERY run/cycle start after header write — the only bound D-05 full-fidelity capture needs | closed |
| T-12-05 | Information disclosure (argv + output in local logs) | run_start argv / body text / VCS | low | mitigate | No env-var capture anywhere (argv-only, D-04); WR-02 header credential redaction (`CREDENTIAL_PATTERN`); `.gitignore` gains `.spm-cache/` so run logs never enter VCS | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-12-02 | T-12-02 | `--log-dir` is same-user local input; no untrusted boundary crossed (research Security Domain V5) | Plan-time disposition, confirmed at audit | 2026-09-01 |
| AR-12-03 | T-12-03 | Symlink swap requires local write access to the project dir — same-trust attacker already has broader reach; prune's unlink-only surface minimizes blast radius | Plan-time disposition, confirmed at audit | 2026-09-01 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-09-01 | 5 | 5 | 0 | gsd secure-phase (L1 short-circuit: plan-time register, threats_open 0, asvs_level 1) |

Evidence basis: 12-VERIFICATION.md truth table (retention group specs `run_log_spec.rb:302-426` for T-12-04; `main_run_log_spec.rb` byte-parity/exit-shape for the capture seams), per-plan SUMMARY Threat Flags (12-02/03/04/05 all "None — no security-relevant surface beyond the plan's threat_model"), and live session probes (zero `ENV[` reads across run_log.rb/sh.rb/main.rb confirming D-04 argv-only capture; `redact_credentials` behavior verified against the production seam).

Documented residual (non-blocking, Info per 12-REVIEW.md): IN-08 — `CREDENTIAL_PATTERN` misses empty-user `:token@` and literal-`/` password forms; reproduced live at audit time. Redaction is header-only by design (D-05 body verbatim). Carried as Info, user-accepted in 12-UAT.md Test 2.

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-09-01
