---
phase: "11"
slug: "homebrew-release-automation"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-08-31"
---

# Phase 11 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.
> Mid-phase operator pivot recorded: GitHub App token → write-access deploy key (blocking-human
> checkpoint, 2026-08-31). App-token threats (T-11-03/04/07) are re-evidenced against the
> deploy-key architecture actually shipped.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| operator → repo secrets | deploy key private key crosses from executor temp dir into repo secret storage via `gh secret set` (masked) | SSH private key (high sensitivity; value never printed) |
| CI → external tap repo | update-tap job authenticates to `phuongddx/homebrew-spm-cache` with the deploy key | formula edits (public data) + write credential use |
| public release artifact → runner | release tarball downloaded and integrity-gated before hashing | public bytes; untrusted until gzip-magic gate passes |
| dispatch input → run bodies | `tag` workflow_dispatch input crosses into scripts via step env only | operator-supplied string; validated before use |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-11-01 | Spoofing/Tampering | trigger surface | high | mitigate | Trigger set pinned to `release[published]` + `workflow_dispatch`; structural spec asserts the exact key set — no `pull_request` trigger addable silently | closed |
| T-11-02 | Tampering/EoP | tag input reaching run bodies | high | mitigate | `DISPATCH_TAG` env indirection only; strict semver validation (WR-01 `ec51795`, tightened from v-then-digit) + sed-metacharacter-safe substitution; injection-guard spec bans context expansion of inputs/event families in run bodies | closed |
| T-11-03 | Info Disclosure | credential material in logs | medium | mitigate | Guard step prints secret NAMES only; post-pivot no minted token exists at all; Actions auto-masks; live logs (runs 1–6) show names only | closed |
| T-11-04 | EoP | over-scoped credential | high | mitigate | **Pivot-equivalent**: write deploy key id 161755962 on `phuongddx/homebrew-spm-cache` ONLY (`read_only:false`, `verified:true`, API-checked 2026-08-31); deploy keys cannot touch workflows or other repos; ambient `github.token` held at `permissions: contents: read` | closed |
| T-11-05 | Tampering | formula edit substitution | high | mitigate | Anchored full-line patterns, exactly-one-match gate, `grep -Fqx` postconditions — live fail-first (run 1: 0-match red, fixed `8ac4bd6`) and live correct edit (run 6: formula delta exactly url+sha) | closed |
| T-11-06 | Repudiation/Integrity | silent publish failure | high | mitigate | `set -euo pipefail` everywhere; suppression banned file-wide by spec; only zero-work exit is the explicit `::notice::` no-diff branch (live runs 1–5); push unguarded (live run 6: `ee27cc7` pushed); concurrency group | closed |
| T-11-07 | Info Disclosure | credential reuse across jobs | low | mitigate | Post-pivot: no token to reuse; verify-publish runs anonymous against the public tap (env: `HOMEBREW_NO_AUTO_UPDATE`, `EXPECTED_VERSION` only) | closed |
| T-11-08 | Tampering | downloaded tarball | high | mitigate | `curl -fL --retry 3` + non-empty + `1f8b` gzip-magic gate strictly before digest (spec pins index order; live in all 6 runs); asset-preference fix `c200a43` pins hash+url to one byte source | closed |
| T-11-GATE-01 | Info Disclosure | key/app-id handling at the gate | high | mitigate | Gate was blocking-human and never auto-approved (executor halted, surfaced to user); keypair generated in temp, private key never printed, temp files deleted; verification queries names only | closed |
| T-11-GATE-02 | EoP | credential installed beyond tap / workflow scope | high | mitigate | Deploy key scoped to the single tap repo; deploy keys carry no workflow scope by construction; single-repo install verified via API | closed |
| T-11-DRY-03 | Tampering | wrong/injected dry-run tag | low | mitigate | Fixed existing tag v0.3.0; strict shape validation + release-existence check before any credential or tap access (live runs) | closed |
| T-11-DRY-04 | Repudiation | dry-run outcome misread | medium | mitigate | `11-LIVE-RUN.md` records 6 runs: per-job conclusions, log excerpts, expected-red rationale | closed |
| T-11-SC | Supply chain | third-party actions | low | accept | Post-pivot only `actions/checkout` remains — pinned by full 40-char SHA (WR-03 `a505521`), stronger than the plan's tag-reference posture; `create-github-app-token` removed by the pivot | closed (accepted, hardened) |
| T-11-CLI-01 | Tampering | `Main.run` --version intercept | low | accept | One string equality check on `argv[0]`; argv never evaluated/interpolated | closed (accepted) |
| T-11-CLI-02 | Info Disclosure | --version output | low | accept | Prints public gem version only | closed (accepted) |

*Severity: critical > high > medium > low — only open threats at or above `high` count toward `threats_open`.*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-11-01 | T-11-SC | Official GitHub actions only; checkout now SHA-pinned; no registry packages installed | plan (11-02), hardened by WR-03 | 2026-08-30 |
| AR-11-02 | T-11-CLI-01/02 | Intercept is a constant-print on one argv equality; output is already-public version | plan (11-01) | 2026-08-30 |
| AR-11-03 | REL-04 pivot (T-11-03/04/07 context) | Deploy key is a long-lived machine credential (non-human, non-expiring) instead of a scoped minted App token — operator-authorized substitute per locked decision; scoped to one repo, no workflow reach | operator (blocking-human checkpoint) | 2026-08-31 |

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-08-31 | 15 | 15 | 0 | orchestrator (L1, ASVS 1 short-circuit; evidence from 6 live CI runs 2026-08-30/31) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-08-31
