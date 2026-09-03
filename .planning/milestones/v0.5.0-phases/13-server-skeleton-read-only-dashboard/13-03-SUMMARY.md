---
phase: 13-server-skeleton-read-only-dashboard
plan: 03
subsystem: web
tags: [web, frontend, offline-assets, vanilla-js, cytoscape, dashboard, ui-spec]

requires:
  - phase: 13-server-skeleton-read-only-dashboard plan 01
    provides: Web::Server/Web::Router serving /assets/* + GET /?token=, Web::Assets resolver with content types, spec/support/web_server_boot.rb hermetic boot helper
  - phase: 13-server-skeleton-read-only-dashboard plan 02
    provides: "/api/state + /api/doctor + /api/graph payload contracts (same-wave; consumed as-pinned, zero key reconciliation needed)"
provides:
  - lib/spm_cache/web/assets/index.html (48px header bar, 1280px column, three panels in locked order, Refresh ×2 + Run Doctor, Loading… shells, graph canvas mount + legend, three relative-only asset refs)
  - lib/spm_cache/web/assets/styles.css (full 13-UI-SPEC token sheet: spacing scale as --space-* multiples of 4, all 13 locked colors, both font stacks, four typography roles, badges on 10%-alpha fills, 480px canvas, 24px fix-hint indent)
  - lib/spm_cache/web/assets/app.js (312-LOC vanilla ES module: token bootstrap → sessionStorage → replaceState → render, X-SPM-Token fetch layer with 401/403 full-page state, state table + 5s auto-poll, on-demand doctor with Running… + ↳ fix hints, vendored-cytoscape graph with macro diamonds + legend)
  - lib/spm_cache/web/assets/cytoscape.min.js (v3.34.2 vendored from the official dist once at execution time; MIT attribution preserved; first-line version comment with no scheme URL; 435,643 bytes)
  - spec/web_frontend_spec.rb (67 served-byte/file-byte pins: offline gate, copy strings verbatim, vocabulary maps, ordering, LOC budget, gemspec membership)
affects:
  - 13-04 (integration matrix serves these assets end-to-end; the GET /?token= 200 expectation starts here)
  - 13-VALIDATION (manual browser walkthrough: token URL cleanup, three panels, polling, Run Doctor, graph render, error states — the automation pins bytes, the walkthrough verifies behavior)
  - 14 (log-stream panel joins the same panel/header/stamp conventions)
  - 16 (node click affordances are explicitly deferred; app.js registers no node handlers)

actuals:
  tokens: 120003   # chars/4 over the realized diff (44,372 first-party chars + the 435,643-char vendored cytoscape.min.js ≈ 109K of the total); plan estimated 45000 at confidence low — the miss is the vendored blob, not the authored surface (~11K tokens)
  tasks: 3
  commits: 6

tech-stack:
  added:
    - "cytoscape v3.34.2 (vendored dist committed as a static asset — zero npm surface, never fetched at runtime; served from /assets/ inside the gem)"
  patterns:
    - "Source-contract specs: no JS runtime in CI, so every behavioral contract is a byte-level pin on served/file content (ordering pins match call shapes like /history\\.replaceState\\(/, not comment text) + a throwaway node DOM-stub smoke harness run at execution time (not committed) + the 13-VALIDATION manual walkthrough"
    - "Stored-XSS defense by construction: app.js contains zero innerHTML/insertAdjacentHTML — every dynamic string (package names, check messages, fix hints from a hostile repo) flows through el()/textContent; smoke-verified with <script>/<img onerror> fixtures rendered inert"
    - "Offline gate scoped per checker finding: first-party assets (index.html, app.js, styles.css) are byte-grepped for scheme URLs and cdn. — zero matches; the vendored cytoscape is pinned structurally instead (first-line version comment with no scheme URL, >300KB, committed, gemspec files membership) because its bundled MIT attribution legitimately names external hosts"
    - "Stamps derive from SERVER timestamps only (envelope generated_at / graph_generated_at); Date.now() is absent from app.js (T-13-16 pin)"

key-files:
  created:
    - lib/spm_cache/web/assets/index.html
    - lib/spm_cache/web/assets/styles.css
    - lib/spm_cache/web/assets/app.js
    - lib/spm_cache/web/assets/cytoscape.min.js
    - spec/web_frontend_spec.rb
  modified:
    - spec/web_server_spec.rb (the two GET /?token= 404 gap examples flipped to 200 — the documented 13-01 fill-in point; both now boot with the real Web::Assets root)

key-decisions:
  - "CTAs per the binding UI-SPEC action text: Refresh on Cache State + Dependency Graph only, Run Doctor on Doctor (the plan behavior bullet's '(three)' counts Refresh occurrences across the served copy — the two button labels plus the baked empty-state body reference — not three buttons)"
  - "Empty-state/error copy strings live in app.js (rendered conditionally); Task 1's served-HTML pins cover title/panels/buttons/Loading…, and the full copy catalog is pinned across the asset set by Tasks 2–3 — every UI-SPEC string is in the served bytes by end of plan"
  - "Graph node colors + legend reuse one NODE_COLOR map in app.js while table badges use styles.css classes — cytoscape needs literal hex values, so the palette exists twice by necessity, both pinned by specs"
  - "node[hasMacro=\"true\"] selector kept verbatim from the cachemap.js.template precedent (existing production behavior for boolean data fields)"
  - "Stamps render in the viewer's local timezone from server ISO timestamps (plan: 'zero-padded HH:MM:SS local time')"
  - "Poll loop stops itself when the token-invalid page replaces the panels (panels gone ⇒ no state-body to refresh); failed polls keep last rows and never stop the loop while panels exist"

requirements-completed: [WEB-04, DASH-01, DASH-02, DASH-03]

coverage:
  - id: WEB-04
    description: "Fully-offline load: first-party assets carry zero scheme-absolute URLs and zero cdn. references; cytoscape structurally pinned and served from /assets/; GET /?token= serves the index"
    verification:
      - kind: unit
        ref: "spec/web_frontend_spec.rb offline gate + vendored cytoscape groups (version comment, >300KB, application/javascript serving, gemspec membership)"
        status: pass
      - kind: unit
        ref: "spec/web_server_spec.rb GET /?token= 200 text/html examples (this plan's gap closure)"
        status: pass
  - id: DASH-01
    description: "State table: Package/Config/Size/State/Fidelity, STATUS_CLASS vocabulary, ◆ macro prefix, mono humanBytes, null-state '—', fidelity colors, empty state with .cmd spans, 5s auto-poll keeping last rows"
    verification:
      - kind: unit
        ref: "spec/web_frontend_spec.rb state table + polling/stamps groups (source pins)"
        status: pass
      - kind: manual-pending
        ref: "13-VALIDATION browser walkthrough (the plan's designated behavior check)"
        status: pending
  - id: DASH-02
    description: "Doctor panel: markers ✓/!/✗, ↳ fix hints at 24px indent, summary from data.summary, 'Cached — generated at' stamp, has_run empty state, Run Doctor → Running… + ?run=1, never auto-polled"
    verification:
      - kind: unit
        ref: "spec/web_frontend_spec.rb doctor panel group (source pins incl. single-timer proof)"
        status: pass
      - kind: manual-pending
        ref: "13-VALIDATION browser walkthrough"
        status: pending
  - id: DASH-03
    description: "Graph panel: vendored cytoscape with elements as-served, status palette, macro diamonds, grid layout, 12px-swatch legend top-right, spm-cache use empty affordance, MMM d, HH:MM stamp from graph_generated_at, non-clickable nodes"
    verification:
      - kind: unit
        ref: "spec/web_frontend_spec.rb graph panel group (source pins incl. no-.on() proof, 300–400 LOC budget)"
        status: pass
      - kind: manual-pending
        ref: "13-VALIDATION browser walkthrough"
        status: pending

duration: 25min
completed: 2026-09-01
status: complete
---

# Phase 13 Plan 03: Offline frontend — index.html + styles.css + app.js + vendored cytoscape Summary

**The user-facing half of the dashboard shipped fully offline: a dark-first 1280px three-panel page (Cache State / Doctor / Dependency Graph) implementing every 13-UI-SPEC dimension verbatim — locked token bootstrap, X-SPM-Token fetch layer, 5s honest auto-poll, on-demand doctor with the terminal's ✓/!/✗ + ↳ vocabulary, and a vendored-cytoscape v3.34.2 nodes-only graph with macro diamonds — in 312 lines of framework-free JavaScript with zero CDN/scheme references in first-party assets; full suite 723 examples green (608 baseline + 13-02's additions + 84 here).**

## Performance

- **Duration:** ~25 min
- **Tasks:** 3 (each RED-then-GREEN, 6 commits)
- **Files:** 6 (5 created, 1 modified) + the 435KB vendored dist; 1,174 first-party lines added

## What Shipped vs Plan

- Task 1 — static skeleton: index.html (header bar, three panels, Loading… shells, graph canvas + legend hooks, three relative-only refs), styles.css (every locked token), vendored cytoscape v3.34.2 with the version-comment/size/gemspec structural pins, the two spec/web_server_spec.rb 404→200 gap closures. Offline gate green.
- Task 2 — app.js core: locked bootstrap order (sessionStorage → replaceState before boot), request() envelope consumer with 401/403 full-page copy, state table (columns, vocabulary map, ◆ prefix, humanBytes, null-state dash, fidelity colors), pollSeconds loop with keep-last-good errors, disable-while-in-flight Refresh.
- Task 3 — panels: doctor renderer (markers, ↳ hints, server summary, cached stamp, Running… swap, ?run=1, single-timer proof), graph renderer (elements as-served, grid, status selectors, hasMacro diamonds, legend, MMM d stamp from graph_generated_at, zero-nodes guard, no node handlers).

Beyond the plan's source pins, all ten render paths were executed at development time against a node DOM-stub smoke harness (table/empty/error/401, doctor empty/run/run-button, graph empty/present — including `<script>`/`<img onerror>` hostile strings rendered inert). The harness is throwaway and not committed; the plan's designated behavior check remains the 13-VALIDATION manual browser walkthrough.

## Deviations from Plan

None — plan executed exactly as written. Two clarifications (documented, not deviations):

- The Task 1 behavior bullet's `Refresh` (three) is satisfied by the two button labels plus the empty-state copy reference; the binding UI-SPEC and the Task 1 action text both lock CTAs to Refresh ×2 + Run Doctor ×1, which is what shipped.
- The Task 1 gemspec-membership pin covers the three Task-1 assets; app.js membership is pinned from Task 2 onward (the Dir glob only lists existing files).

## Threat Flags

All four register dispositions implemented as planned; no surface beyond the model was introduced:

| Flag | File | Description |
|------|------|-------------|
| threat_mitigated: T-13-13 | lib/spm_cache/web/assets/app.js | Stored-XSS defense: zero innerHTML/insertAdjacentHTML in the file (spec-pinned); every dynamic string flows through el()/textContent — hostile repo strings (module names, check messages, fix hints) render inert; smoke-verified with `<script>alert(1)</script>` / `<img onerror>` fixtures |
| threat_mitigated: T-13-14 | lib/spm_cache/web/assets/cytoscape.min.js | Supply chain: dist fetched once at execution time from the official registry (unpkg → cytoscape@3.34.2), committed, never fetched at runtime; structural pins (first-line version comment with no scheme URL, 435,643 bytes > 300KB, application/javascript serving, gemspec spec.files membership); MIT attribution preserved verbatim |
| threat_mitigated: T-13-15 | lib/spm_cache/web/assets/app.js | Token hygiene: sessionStorage only, URL cleaned via replaceState before first render (spec-pinned ordering), X-SPM-Token header on every request, token value never rendered (grep pins), server sets no-store (13-01) |
| threat_mitigated: T-13-16 | lib/spm_cache/web/assets/app.js | Honest staleness: every stamp (state Updated, doctor Cached —, graph Updated MMM d) derives from server timestamps (envelope generated_at / graph_generated_at); Date.now() absent from the file (spec-pinned); failed polls keep last rows beside the error copy |

## Known Stubs

None — no stubs, placeholders, or unwired data paths. (The stamp spans in index.html start empty by design; app.js fills them — that is the Loading… initial state, not a stub.)

## Self-Check: PASSED
