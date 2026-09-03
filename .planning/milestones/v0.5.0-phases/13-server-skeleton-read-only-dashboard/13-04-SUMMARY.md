---
phase: 13-server-skeleton-read-only-dashboard
plan: 04
subsystem: web
tags: [web, integration, security-matrix, packaging, webrick, offline, gemspec]

requires:
  - phase: 13-server-skeleton-read-only-dashboard plan 01
    provides: Web::Server/Router/Middleware as shipped (the route/auth matrix under test), Web::Assets resolver, spec/support/web_server_boot.rb request helpers
  - phase: 13-server-skeleton-read-only-dashboard plan 02
    provides: /api/state + /api/doctor + /api/graph read models with the pinned {status,data,generated_at} payload contracts
  - phase: 13-server-skeleton-read-only-dashboard plan 03
    provides: the four real offline assets under lib/spm_cache/web/assets/ that the page-load sequence and packaging pins consume
provides:
  - spec/web_integration_spec.rb (the phase's weld: ONE before(:all) port-0 boot walking the exhaustive 25-cell route × case matrix, the CP13 drive-by shapes on every /api/* route, the full browser page-load sequence with assets parsed from the served HTML, the header sweep, the localhost allowlist entry, and a <15 s whole-file runtime pin — the standing regression net Phase 15 inherits before adding POSTs)
  - spec/web_packaging_spec.rb (T-13-19: all four dashboard assets in Gem::Specification.files + a glob-ships-the-dir pin over every file on disk under web/assets; CP8: webrick >= 1.8, < 2 requirement-object pin + in-process require smoke; real gem-build smoke over a tmpdir packaging tree; offline-set twin — first-party assets byte-grepped, cytoscape structurally pinned, never byte-gated)
affects:
  - 13-VALIDATION (the two spec files are the evidence base for the WEB-04 sign-off rows; the manual browser walkthrough and true-offline load are the human half)
  - 14 (copies the integration boot as its streaming-test fixture)
  - 15 (adds POST endpoints behind the gate with zero new middleware work — now test-backed by the method-agnostic rows)

actuals:
  tokens: 4200    # chars/4 over the realized diff (16,915 added chars across 2 commits); plan estimated 22000 at confidence low — verification-net specs, not feature surface
  tasks: 2
  commits: 2

tech-stack:
  added: []   # pure proof: no new runtime surface, no production edits at all
  patterns:
    - "Table-driven matrix with self-naming rows: ROUTES × CASES product generates one it per cell, so a regression names the exact route and attack shape (T-13-17)"
    - "One boot per FILE, not per example: before(:all) + order: :defined; the runtime pin (T-13-20) reads a monotonic clock captured before the boot, so the bound covers boot + all ~60 requests"
    - "Build smoke over a minimal packaging tree: gemspec Dir[] globs evaluate relative to CWD, so a tmpdir holding lib+bin+top-level entries (tools/ and assets/ as skeleton dirs) builds a real .gem without copying the 583 MB tools tree or polluting the working tree"
    - "Offline twin scoped per the revised CP7 checker finding: first-party assets byte-grepped for scheme URLs / cdn.; cytoscape pinned structurally (first-line version comment, >300 KB, spec.files membership) — never byte-gated"

key-files:
  created:
    - spec/web_integration_spec.rb
    - spec/web_packaging_spec.rb
  modified: []   # lib/spm_cache/web/middleware.rb was in files_modified for the gap case — no gap surfaced, so the file is untouched

key-decisions:
  - "No middleware gap found: all 25 matrix cells, the drive-by trio on every /api/* route, and the page-load sequence passed against 13-01/13-02/13-03 as shipped on the first full run — the plan's 'largely pass immediately' expectation held, so middleware.rb was never edited and every expectation is the prior contracts verbatim"
  - "The no_token/wrong_token cells on / and /assets/styles.css PIN the token gate's scope, not its absence: / answers the bootstrap 302 and /assets/* serve 200 because the locked matrix exempts them (assets cannot send headers, carry zero project data) — the 401s live only on the /api/* rows"
  - "Drive-by rows carry a VALID token on the Origin/Host rejects — proving gate order (Host → Origin → token) fires even with a legitimate token, the strongest reading of CP13"
  - "/api/state's happy cell asserts envelope + payload keys only (packages/summary/poll_seconds), not row contents: Inventory.scan's default cache_root is the real ~/.spm-cache (HOME-derived constant), so the cell is machine-independent while still proving the full real wiring answers 200"
  - "Doctor's never-run stamp pinned end-to-end: envelope generated_at nil (not re-stamped) alongside data.has_run false — DASH-02's honesty contract, now proven through a real socket"
  - "Real gem-build smoke kept in the automated suite (not deferred to 13-VALIDATION): the scoped tmpdir tree builds in ~1 s, so the built .gem's file list — not just the gemspec's evaluation — proves the four assets package"

requirements-completed: [WEB-04]

coverage:
  - id: WEB-04
    description: "Reject matrix proven on every route + every attack shape from one real boot; drive-by simulation (foreign-Origin POST, same-Host no-Origin tokenless form POST, Origin null, unknown method/path); packaging: gem ships all four assets, webrick >= 1.8 < 2 declared; offline set re-asserted over the packaged set"
    verification:
      - kind: integration
        ref: "spec/web_integration_spec.rb (42 examples: 25-cell route × case matrix over /, /assets/styles.css, /api/{state,doctor,graph}; 11 CP13 drive-by/404 examples; 3 page-load sequence examples; header sweep; localhost:{port} allowlist entry; <15 s runtime pin; single before(:all) port-0 boot)"
        status: pass
      - kind: unit
        ref: "spec/web_packaging_spec.rb (7 examples: four assets + glob-ships-the-dir in spec.files, webrick requirement window pin, require smoke, real gem-build smoke, offline twin first-party byte gate, cytoscape structural pins)"
        status: pass
      - kind: manual-pending
        ref: "13-VALIDATION: real-browser walkthrough + true-offline load (the human half of SC3/SC4/SC5 sign-off)"
        status: pending

duration: 11min
completed: 2026-09-01
status: complete
---

# Phase 13 Plan 04: Cross-route hardening matrix + packaging/offline proof (phase weld) Summary

**The phase's security and shipping claims are now proven end-to-end from one real server boot: a 25-cell route × case matrix (every route × happy/foreign-Origin/spoofed-Host/no-token/wrong-token) plus the CP13 drive-by shapes on every /api/* route all passed against 13-01..13-03 as shipped with zero production edits, while the packaging pins prove the built gem carries all four offline dashboard assets and declares webrick >= 1.8, < 2 — full suite 772 examples green (723 pre-existing + 49 new).**

## Performance

- **Duration:** ~11 min
- **Tasks:** 2 (verification-net specs: single commit each, per the plan's RED-is-vacuous note)
- **Files:** 2 created, 373 lines added, zero production edits

## What Shipped vs Plan

### Task 1 — spec/web_integration_spec.rb (1b6f4df)
As planned: ONE before(:all) port-0 boot (tmpdir project with a two-entry fixture graph.json, real Web::Assets root, real read models — no injection seams). Table-driven 25-cell matrix where every row names itself; drive-by trio (foreign-Origin POST with valid token → 403, same-Host no-Origin tokenless POST → 401, Origin "null" GET → 403) on every /api/* route; passing-gate unknown-method (PUT) and unknown-path 404s; the browser page-load sequence (exact-token bootstrap 302 → index containing all three panel titles → the three assets parsed FROM the served HTML with content types → the three API envelopes with the 13-02 payload keys, doctor's never-run stamp nil); header sweep (X-Frame-Options DENY + no-store over the sequence responses); the localhost:{port} allowlist entry; and the <15 s whole-file runtime pin (actual: 0.18 s).

### Task 2 — spec/web_packaging_spec.rb (f12da58)
As planned: Gem::Specification.files carries all four assets plus a glob-ships-the-dir pin (every file on disk under web/assets must be packaged — a future glob narrowing fails CI); the webrick requirement pinned through the requirement object (satisfied_by 1.8/1.9.2, not 2.0/2.1) with the in-process require smoke; a REAL gem-build smoke over a scoped tmpdir packaging tree (~1 s, skipped if the gem CLI is absent); and the offline-set twin reading assets from the spec's own file list — first-party trio byte-grepped for scheme URLs/cdn., cytoscape structurally pinned (version first line, >300 KB), never byte-gated per the revised CP7-scoped gate.

## Deviations from Plan

None — plan executed exactly as written. No middleware/router/read-model gap surfaced (the plan's permitted production edit was never needed), no gemspec change was required (13-01's `{lib,…}/**/*` glob and dependency block already met both pins — this plan makes them un-regressible).

### Clarifications (documented, not deviations)

- The matrix's no_token/wrong_token cells on the two non-API routes pin the gate's documented SCOPE (302 bootstrap on /, 200 on /assets/*): the locked 13-01 matrix exempts them from the token check; the 401 rows live only on /api/*.
- Example counts: the integration file owns 42 examples (45 in a solo run includes spec_helper's inline 3), the packaging file owns 7 (10 solo) — the combined full suite counts the helper block once: 723 pre-existing + 49 new = 772.

## Threat Flags

All four register dispositions implemented; no surface beyond the plan's threat_model was introduced:

| Flag | File | Description |
|------|------|-------------|
| threat_mitigated: T-13-17 | spec/web_integration_spec.rb | Auth-gate regression net: the 25-cell route × case matrix is the standing proof — any middleware/router change that opens a cell fails the suite by name; Phase 15 inherits this gate before adding POSTs |
| threat_mitigated: T-13-18 | spec/web_integration_spec.rb | Drive-by coverage on every /api/* route: foreign-Origin POST (403 even with a valid token), same-Host no-Origin tokenless form POST (401), Origin "null" sandboxed-iframe GET (403) — the three shapes a browser page can actually produce against localhost (CP13) |
| threat_mitigated: T-13-19 | spec/web_packaging_spec.rb | Packaging integrity: all four dashboard assets pinned inside Gem::Specification.files plus the glob-ships-the-dir pin (every file on disk under web/assets must package) and a real gem-build smoke over the built .gem's file list — a future glob narrowing fails CI instead of shipping a dead dashboard |
| threat_mitigated: T-13-20 | spec/web_integration_spec.rb + spec/web_packaging_spec.rb | Socket/runtime discipline per the REVISED CP7 wording: exactly ONE exhaustive cross-route integration spec with a single before-all port-0 boot and a pinned <15 s runtime bound (actual 0.18 s); the single-feature thread-booted serve-through examples in the unit specs (web_server/web_state/web_graph/web_doctor/web_assets) remain as-is — hermetic loopback, ephemeral port, tmpdir; the packaging spec boots nothing at all |

## Known Stubs

None. Both files are pure verification nets over fully-wired production surface; the 13-VALIDATION manual walkthrough items are the plan's designated human half, tracked as manual-pending in coverage, not stubs.

## Verification

- Full suite: **772 examples, 0 failures** (723 pre-existing + 42 integration + 7 packaging; dry-run of the pre-existing set re-counted at exactly 723)
- Both task commits present: 1b6f4df (integration matrix), f12da58 (packaging pins)
- Plan's verification command: **52 examples, 0 failures** (`bundle exec rspec spec/web_integration_spec.rb spec/web_packaging_spec.rb` — 42 + 7 new plus spec_helper's inline block counted once); integration file runs in 0.18 s against its 15 s pin

## Self-Check: PASSED

Both created files exist on disk; both commits (1b6f4df, f12da58) present in history on gsd/v0.5.0-web-interface; ROADMAP plan progress updated (4/4 — phase 13 execution complete).
