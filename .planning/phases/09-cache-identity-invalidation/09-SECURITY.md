---
phase: 09
slug: cache-identity-invalidation
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: 2026-08-29
---

# Phase 09 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Provenance sidecar (`.provenance.json`) → `Cache.swift`'s `hit()` | The sidecar now GATES a real cache-hit decision (not just a diagnostic display, as in Phase 8) — a shared/remote cache backend could in principle serve a corrupted or crafted sidecar alongside its xcframework. | JSON sidecar file, cache-backend-controlled |
| Host `spm-cache.lock`-derived pin (`pkg.pinValue`) → `hit()`'s `currentPin` argument | Local toolchain-derived data (Phase 6/7's already-reconciled lockfile), re-read as trusted input; no network/attacker-controlled input at this layer. | Local lockfile pins, developer-owned |
| On-disk `spm-cache.lock` → `fast_path?`'s version-stamp read | Same local, developer-owned lockfile every other `Installer` code path already trusts fully (Phase 6/7/8); read one statement earlier than `sync_lockfile` would normally populate it. | Local lockfile stamp, developer-owned |
| `cache clean`'s `Dir.glob`-driven sweep → `FileUtils.rm_f` | A local filesystem deletion path, scoped by a suffix-stripped basename match against the SAME cache directory — no user-supplied path traversal input. | Local cache-dir filenames |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-09-01 | Tampering | `<module>.xcframework.provenance.json` read by `hit()` | high | mitigate | `Cache.swift:28-48` — every parse anomaly (missing file, unreadable data, non-Hash root, missing/non-dictionary `pins` key, pin disagreement) returns `nil`: a malformed/tampered sidecar can only force a safe extra rebuild, never a false hit. Verified by 9 passing `CacheTests.swift` cases (V5 fail-safe parsing, D-04) and real-binary specs. | closed |
| T-09-02 | Spoofing | Cross-project pin identity comparison (`identity`/`currentPin` params) | medium | mitigate | `ProxyGenerator.swift:120` — identity/pin values sourced from the host project's own already-reconciled `spm-cache.lock` (Phase 6/7 trusted local chain); `pkg.name`/`pkg.pinValue`, never `product.name`. Regression-guarded by the two-product Pitfall-3 test. | closed |
| T-09-03 | Information Disclosure | not-graph-pinned sidecar's `pins: {}` write | low | accept | See Accepted Risks Log. | closed |
| T-09-04 | Tampering | On-disk lockfile's `spm_cache_version` stamp, read via a throwaway `Core::Lockfile` | low | accept | See Accepted Risks Log. | closed |
| T-09-05 | Denial of Service (data loss) | `cache clean`'s orphan-sidecar sweep | medium | mitigate | `clean.rb:66-79` — sweep removes a sidecar only when its suffix-stripped basename has NO matching `.xcframework` directory; paired sidecars always survive (D-10), `--dry` reports without deleting. Verified by 6 passing `command_cache_clean_spec.rb` examples. | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

09-03-PLAN.md is documentation-only (no code, no new trust boundary) and contributes no threats.

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-09-01 | T-09-03 | Writing an empty pins hash for vendored-.xcodeproj/no-host-graph packages discloses strictly LESS information than a real sidecar — matches Phase 8's already-audited CACHE-01 four-field privacy contract with no new fields. | Plan 09-01 (plan-time disposition) | 2026-08-29 |
| AR-09-02 | T-09-04 | Same local, developer-owned file every other Installer path already trusts unconditionally (Phase 6/7/8) — no new trust boundary is crossed by reading it one statement earlier than `sync_lockfile` normally would. | Plan 09-02 (plan-time disposition) | 2026-08-29 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-08-29 | 5 | 5 | 0 | claude (gsd-secure-phase, L1 short-circuit) |

L1 short-circuit applied (register authored at plan time, threats_open 0, asvs_level 1): all three
mitigate-dispositions were re-confirmed directly against implementation source (`Cache.swift`,
`ProxyGenerator.swift:120`, `clean.rb:66-79`) and the passing verification-report spot-checks
(387 Ruby examples, 36 Swift tests); accept-dispositions documented above.

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-08-29
