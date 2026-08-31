---
phase: 10
slug: fidelity-regression-coverage
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: 2026-08-30
---

# Phase 10 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Spec fixture JSON → production parsers (`Desc::Target`, `Core::PackageResolved`, lockfile readers) | Fabricated fixture content is consumed by real production parse paths inside the specs | Inert JSON, repo-authored |
| Committed fixtures/sidecars → repository | Test fixture data becomes part of the public repo | Fake identities/URLs/revisions only |
| Tier-3 `system()` invocations → compiled proxy binary | Specs shell out to the local `spm-cache-proxy` binary with pattern arguments | Fixed argv + `Dir.mktmpdir`/`SPMCache::ROOT` paths |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-10-01 (all plans) | Elevation of Privilege | spec/desc-JSON/fixture content | low | accept | See Accepted Risks Log. | closed |
| T-10-02 (all plans) | Information Disclosure | committed fixtures/sidecars | low–medium | mitigate | Fake identities/revisions/URLs only, no credentials or real private-repo URLs — deep code review (10-REVIEW.md, converged) inspected the committed spec and fixture files and confirmed the convention. | closed |
| T-10-03 (all plans) | Tampering | tier-3 `system()` command construction | low | mitigate | Fixed argv against `Dir.mktmpdir`/`SPMCache::ROOT` paths; no fixture-derived free text reaches the command string; reviewer + verifier both traced the command construction (verifier mutation probes exercised the tier-3 legs). | closed |
| T-10-SC (all plans) | Supply chain | package installs | low | accept | See Accepted Risks Log. | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-10-01 | T-10-01 | Fixtures are inert JSON consumed by parsers; no eval/exec of fixture content exists or is added (test-only phase, zero production changes confirmed by verification git-range audit). | Plans 10-01/02/03 (plan-time disposition) | 2026-08-29 |
| AR-10-02 | T-10-SC | Zero package-manager installs this phase; RESEARCH Package Legitimacy Audit records none. | Plans 10-01/02/03 (plan-time disposition) | 2026-08-29 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-08-30 | 12 (4 distinct × 3 plans) | 12 | 0 | claude (gsd-secure-phase, L1 short-circuit) |

L1 short-circuit applied (register authored at plan time, threats_open 0, asvs_level 1): mitigate-dispositions
re-confirmed against the deep code review (10-REVIEW.md — 0 Critical/0 Warning after WR-01/WR-02 convergence,
re-review confirmed) and the goal-backward verification (10-VERIFICATION.md — 23/23 truths, zero production
changes, tier-3 legs traced); accept-dispositions documented above.

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-08-30
