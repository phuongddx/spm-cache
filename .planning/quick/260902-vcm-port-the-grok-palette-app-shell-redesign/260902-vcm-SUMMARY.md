---
phase: 260902-vcm-port-the-grok-palette-app-shell-redesign
plan: 01
subsystem: web
tags: [web, frontend, app-shell, redesign, vanilla-js, grok-palette, ui-spec]
status: complete

requires:
  - phase: 13-server-skeleton-read-only-dashboard
    provides: Web::Server/Web::Router serving /assets/* + GET /?token=, Web::Assets resolver, /api/state /api/doctor /api/graph payload contracts
  - phase: 14-live-log-streaming
    provides: log.js SSE wire contract (hello/entry/switch/notice), the DOM-id contract log.js binds to
  - phase: 15-ui-build-controls
    provides: build/rollback POST flows and the row state machine app.js/log.js still drive unchanged
  - phase: 16-package-toggles-panel-completion
    provides: the toggle/apply/revert POST flows and the sixth Cached column app.js still drives unchanged
provides:
  - lib/spm_cache/web/assets/index.html (app-shell layout — topbar / alert-rail / nav-rail / 4 surfaces — every DOM-id-contract id preserved, zero fabricated data on cold load)
  - lib/spm_cache/web/assets/styles.css (Grok/xAI monochrome palette wholesale copy from the OpenDesign mockup, adapted for the real JS's class vocabulary)
  - lib/spm_cache/web/assets/app.js (nav-rail surface switching, cache filter/chips, doctor tallies/badges — state/doctor/graph render into the new static containers)
  - lib/spm_cache/web/assets/log.js (banner/switch-notice/follow-pill/filter-pill patch static nodes; topbar status/command mirror; #log-count)
  - spec/web_frontend_spec.rb (rewritten top to bottom: 213 examples describing the new real structure/copy/CSS tokens)
affects:
  - any future phase touching the dashboard frontend inherits the app-shell structure (topbar/alert-rail/nav-rail/surfaces) and the Grok palette tokens as the new baseline
  - spec/web_integration_spec.rb (one assertion updated: the skip-link's in-page anchor is excluded from the asset-resolution gate)

actuals:
  tokens: 46972   # chars/4 over the realized diff (git diff bf302da..HEAD on the touched files)
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "App-shell layout (100dvh grid: topbar / alert-rail / [nav-rail | surface]) replaces the old single-scroll-column panel stack — one surface visible at a time via .surface.hidden, nav-rail switching by click/1-4/`/`/Escape, persisted in localStorage"
    - "Static-node reuse for JS-driven UI chrome: the sync bar, log banner, switch notice, follow pill, and filter pill all moved from create-and-destroy-per-render to persistent DOM nodes whose .hidden/.textContent/.className are patched in place — click listeners attach ONCE at boot() instead of per-render"
    - "Cold-load honesty preserved through the redesign: every element that could show fabricated data (topbar state pill, doctor tallies, rail badges, log identity card, recent-runs dropdown) ships empty/placeholder in static markup and is filled only by a real fetch/stream"
    - "Doctor's cold-load .loading placeholder is patched/removed in place rather than replaced via a full-body renderEmpty() — since #check-list/#doctor-summary are now persistent siblings, a full-body replace on the (very common) has_run:false path would have permanently orphaned them the first time a real Run Doctor click landed has_run:true"

key-files:
  created: []
  modified:
    - lib/spm_cache/web/assets/index.html
    - lib/spm_cache/web/assets/styles.css
    - lib/spm_cache/web/assets/app.js
    - lib/spm_cache/web/assets/log.js
    - spec/web_frontend_spec.rb
    - spec/web_integration_spec.rb (one line: skip-link fragment excluded from the asset-resolution gate)

key-decisions:
  - "Kept the plan's locked decisions 1-8 verbatim: OpenDesign artifacts stripped, hardcoded mock values deleted (progress meter, rail-facts, fake run options, fake doctor tallies), banner/switch/pill/sync-bar moved to static-with-real-wiring, #graph-wrap no longer starts hidden, cytoscape untouched, dark-only/offline/token/textContent-only/[hidden] preserved"
  - "Doctor's !has_run empty state reuses the cold-load .loading paragraph (text swapped, never removed) instead of a full-body renderEmpty() — renderEmpty() would destroy the now-persistent #check-list/#doctor-summary nodes on the very first (and most common) cold-load path, breaking every subsequent Run Doctor click; graph's own !data.present branch keeps its pre-existing renderEmpty() call unchanged per the plan's explicit 'existing branch still applies' instruction, since that panel is refresh-only and the destroy-on-empty risk already existed pre-port"
  - "state's zero-total-packages case and the filter-yields-zero-rows case share one #state-empty indicator — the redesign's own markup scopes #state-empty to the filter case only, and a genuinely empty cache trivially satisfies 'zero rows match any filter' too, so no second message system was needed"
  - "Separated the sync bar's static honesty sentence (no id, never touched by JS) from #sync-message (the click-feedback slot) — the mockup's own markup merges them into one id, which would let saySync()'s className overwrite wipe the honesty sentence's styling and, on saySync(''), hide it entirely; kept as two nodes to preserve the original two-slot semantics"
  - "Fixed the switch-notice copy back to the original 'switched to new run — previous: ' (COPY.switchNotice) rather than the mockup's own 'You are viewing an earlier run — the live tail is paused.' — the two describe genuinely different scenarios (auto-switch-away vs manually viewing a historical run from the dropdown) and only the former is what this code path actually does"
  - "Removed the decorative .conn-dot span from #conn-pill — log.js's setPill() sets textContent directly (the glyph is embedded in the COPY string itself), which would silently strip any nested dot span on the very first render; dead markup removed rather than left to be invisibly destroyed"
  - "Dropped the now-meaningless 'exactly one accent-color declaration' CSS invariant from the old spec — the app-shell deliberately uses accent color in more places (topbar state pill, active rail item, log status, filter pill) than the old single-panel design did; replaced with a direct check that the old blue (#2196F3) never reappears and that .btn-primary is the shell's only solid-fill accent button"

requirements-completed: [QUICK-GROK-SHELL-01]

coverage:
  - id: QUICK-GROK-SHELL-01
    description: "Grok-palette app-shell redesign ported into production with zero fabricated data and zero functional regression"
    tests:
      - "spec/web_frontend_spec.rb — 213 examples (structure, copy, CSS tokens, nav-rail switching, cache filter/chips, doctor tallies/badges, all pre-existing mechanics re-verified against the new targets)"
      - "spec/web_integration_spec.rb — full end-to-end route/asset-serving matrix, unaffected by the port except one fragment-href exclusion"
    manual: "Automated smoke test only (booted the real WEBrick server via spec/support/web_server_boot.rb and curled /, all four assets, and /api/state|doctor|graph|runs — all 200, real JSON payloads, no fabricated values); a full interactive browser walkthrough (click-through of nav-rail/filter/build controls) was not performed in this run — see Deviations"

metrics:
  duration: ~120min
  completed: 2026-09-02
---

# Quick Task 260902-vcm: Port the Grok-Palette App-Shell Redesign Summary

Ported the OpenDesign mockup's Grok/xAI monochrome app-shell redesign (topbar + alert-rail + left nav-rail + 4 switchable surfaces) into the production dashboard, rewiring `app.js`/`log.js` to the new static containers per the redesign's own rewiring notes while preserving 100% of the real fetch/token/SSE/toggle/build/apply/revert logic — and rewrote `spec/web_frontend_spec.rb` end to end (213 examples) to pin the new real structure instead of failing against it.

## What Changed

**`index.html`** — replaced wholesale with the app-shell structure: `topbar` (brand, run-status mirror, build controls, connection pill, port label) → `alert-rail` (rollback confirm bar) → `shell` (nav-rail + `main.surface-main` holding the 4 `section.surface` elements, Run Log visible by default). Every OpenDesign artifact (`data-od-id`, `demo.js` reference, the "Static preview" note) is gone; every hardcoded mock value (progress meter, `rail-facts`, fake run options, fake doctor tallies, fake identity-card content) is gone, replaced with real cold-load placeholders. All 42 ids from the original DOM-id contract survive, plus the new ids the redesign introduces (`rail`, `alert-rail`, `surface-main`, `surface-{run,cache,doctor,graph}`, `topbar-state`, `runstat-cmd`, `log-banner-text`, `log-banner-jump`, `log-switch-btn`, `log-filter-pill`, `log-count`, `log-follow-btn`, `state-filter`, `state-total`, `state-empty`, `chip-n-all`, `doctor-summary`, `check-list`, `rail-badge-cache`, `rail-badge-doctor`).

**`styles.css`** — replaced wholesale with the redesign's Grok-palette stylesheet (`--c-bg:#000000`, `--c-accent:#FFFFFF`, `--c-panel:#171717`, etc.), keeping the load-bearing `[hidden] { display: none !important; }` rule and every `display:flex` override it must outrank. Added a small compatibility patch on top of the pure copy: `.cmd`/`.log-live` accent-text rule (for `#conn-pill`'s connected state and `#log-status`'s running state, which the mockup's own CSS vocabulary didn't cover since its own JS used different class names), and fixed `.conn-pill`'s base color from the mockup's `--c-ok` (green) to `--c-muted` (neutral) so the "connecting" state doesn't render falsely green before a connection exists.

**`app.js`** — `renderState` now writes only into `#state-rows` (a `<tbody>`); the `<thead>`, filter/chip toolbar, and sync bar are static markup it never touches. Added real package-name filtering + 4 state chips (all/hit/missed/other), `#chip-n-all`/`#state-total` derived from the last successful fetch, `#state-empty` for filter-yields-zero, and `#rail-badge-cache` from the real pending count. `renderDoctor` writes checks into `#check-list` and tallies into `#doctor-summary`, reusing the cold-load `.loading` placeholder instead of a full-body replace (see Deviations). Added `showSurface()` nav-rail switching (click, digit keys 1-4, `/` focuses the cache filter, `Escape` blurs), wired to the rail items and a `keydown` listener, persisted to `localStorage`. `renderGraph` no longer force-unhides `#graph-wrap` (it starts visible). `renderTokenInvalid` now replaces the whole `.app` shell. Removed the now-dead `buildSyncBar()`/`barFrozen` — the sync bar's buttons are static and `freeze()` already writes their `disabled` state directly.

**`log.js`** — `showBanner`/`renderSwitchNotice`/`renderPill` now patch static persistent nodes (`#log-banner-text`, `#log-banner-jump`, `#log-switch-btn`, `#log-follow-btn`, `#log-filter-pill`) instead of creating/appending a new element every call; their click listeners attach once at `boot()`. `setCardStatus`/`buildCard` additionally mirror the same derived status/glyph and command into `#topbar-state`/`#runstat-cmd` — no new data source. `#log-count` stays in sync with `ringCount + evicted` on every append/eviction/run-reset. `renderTokenInvalid` replaces the whole `.app` shell, matching `app.js`.

**`spec/web_frontend_spec.rb`** — rewritten top to bottom. Sections whose underlying mechanics didn't change (token bootstrap, fetch/401 handling, polling, doctor/graph fetch failure copy, XSS hygiene, cytoscape vendoring, anchor-rail filter engine, auto-switch/recent-runs, build/rollback/apply/revert POST flows) kept equivalent assertions against the unchanged code. Sections whose targets moved (state table, doctor panel, CSS design tokens, the sync bar, the banner/switch/pill lifecycle, the build-controls location) were rewritten against the new real bytes. Added new describe blocks for the app-shell layout itself (cold-load honesty, static-node wiring, nav-rail switching) and the Grok palette tokens.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Doctor's cold-load empty-state would have orphaned `#check-list`/`#doctor-summary` forever**
- **Found during:** Task 2 (rewiring `renderDoctor`)
- **Issue:** The original `renderDoctor`'s `!data.has_run` branch called `renderEmpty(body, ...)`, which does `body.replaceChildren(...)` — wiping the entire `doctor-body`. Once `#check-list`/`#doctor-summary` became persistent static siblings (this port's own rewiring), that first cold-load call (has_run: false is the common default state) would permanently destroy both nodes; the very next real "Run Doctor" click (has_run: true) would then find `byId('check-list')`/`byId('doctor-summary')` returning `null`.
- **Fix:** `renderDoctor` now reuses the cold-load `.loading` paragraph (swapping its text to "Doctor has not run yet…", never removing it) instead of calling `renderEmpty`, and sets `body.dataset.rendered = '1'` unconditionally so a later fetch failure prepends rather than replaces.
- **Files modified:** `lib/spm_cache/web/assets/app.js`
- **Commit:** c090c4c

**2. [Rule 1 - Bug] The state-sync-bar's honesty sentence and click-feedback slot were merged into one id, letting `saySync()` clobber the sentence**
- **Found during:** Task 2 (rewiring the sync bar to static show/hide)
- **Issue:** The mockup's own static markup uses one `id="sync-message"` node for both the fixed comment-loss honesty sentence AND the click-driven "Applying…"/error feedback. `saySync()` sets `.className`/`.hidden`/`.textContent` on that node — which would wipe the honesty sentence's styling class the first time any feedback message showed, and hide the sentence entirely on `saySync('')`.
- **Fix:** Split into two nodes — a static `.state-sync-text` span (no id, holds the honesty sentence, never touched by JS) and `#sync-message` (starts empty/hidden, patched only by `saySync()`), matching the original two-slot semantics.
- **Files modified:** `lib/spm_cache/web/assets/index.html`
- **Commit:** c090c4c

**3. [Rule 1 - Bug] The skip-link's in-page anchor broke an existing integration test's asset-resolution gate**
- **Found during:** Task 3 full-suite run
- **Issue:** `spec/web_integration_spec.rb`'s "serves every asset referenced by the served HTML" test resolves every `href`/`src` in the document and expects each to serve a real asset. The new `<a class="skip-link" href="#surface-main">` is an in-page fragment, not an asset — resolving it produced a 302 (no token on that bare-path request), a false positive.
- **Fix:** Excluded fragment-only refs (`start_with?('#')`) from the resolution loop in both `spec/web_frontend_spec.rb`'s equivalent check and `spec/web_integration_spec.rb`.
- **Files modified:** `spec/web_integration_spec.rb`, `spec/web_frontend_spec.rb`
- **Commit:** aed6ed9

**4. [Rule 1 - Bug] `#conn-pill`'s decorative dot span would be silently destroyed on first render**
- **Found during:** Task 1 (porting the topbar markup)
- **Issue:** The mockup's `#conn-pill` nests a `<span class="conn-dot">` inside the pill text. `log.js`'s `setPill()` does `pill.textContent = COPY[state]`, which replaces ALL children — the dot would vanish the instant `boot()` runs (essentially immediately, no observable flash), making the markup dead weight.
- **Fix:** Removed the `.conn-dot` span from the static markup; the glyph is already embedded in each `COPY` string (`● connecting…`, `● connected`, `↻ reconnecting…`).
- **Files modified:** `lib/spm_cache/web/assets/index.html`
- **Commit:** 4dcda2b

### Design choices within scope (not bugs, but worth flagging)

- The switch-notice's static sentence was set to the original `'switched to new run — previous: '` (COPY.switchNotice) rather than the mockup's own `'You are viewing an earlier run — the live tail is paused.'` — these describe different real scenarios in this app (an auto-switch away from a run you were watching, vs. manually browsing history via the dropdown), and only the former is what `onSwitchEvent`/`renderSwitchNotice` actually does.
- `#state-empty` (native to the redesign, scoped by the plan's own decision 5 to "shown when a filter yields zero visible rows") also naturally covers the genuinely-empty-cache case, since zero total packages trivially match zero of any filter — no second message system was added, since the plan didn't ask for one and the existing signal is honest either way.
- Dropped the old spec's "exactly one `color: var(--c-accent)` declaration" CSS invariant. The app-shell deliberately uses accent text in more places than the old single-panel design (topbar state pill, active rail item, log-live liveness, the accent-wash active anchor chip) — this is the redesign's own stated visual language ("one accent, twice per screen" refers to solid-fill BUTTONS specifically, not text color), not a regression. Replaced with a direct check that `#2196F3` (old blue) never reappears and `.btn-primary` is the shell's sole solid accent button.

## Known Stubs

None — every element that could show fabricated data ships empty/placeholder in the static markup and is filled only by a real fetch/stream (see Deviations for the two cold-load edge cases that required extra care).

## Threat Flags

None — no new network endpoints, auth paths, file-access patterns, or schema changes at trust boundaries were introduced by this port. The plan's own threat register (T-QP-01 through T-QP-04) covers the surfaces this task touched; all four are already disposed as `mitigate`/`accept` in the plan and remain correctly mitigated: the cache filter/chips only toggle CSS classes on already-safe rendered nodes (T-QP-01), the static-node `.textContent =` patches use the same XSS-safe sink `el()` used internally (T-QP-02), the fabricated topbar metrics were deleted rather than faked (T-QP-03), and no new dependency was introduced (T-QP-04).

## Self-Check: PASSED

- `lib/spm_cache/web/assets/index.html` — FOUND, all 42 DOM-id-contract ids present, zero `data-od-id`/`demo.js`/"Static preview" remnants
- `lib/spm_cache/web/assets/styles.css` — FOUND, `--c-accent: #FFFFFF`, zero `#2196F3`
- `lib/spm_cache/web/assets/app.js` — FOUND, `node --check` OK, zero `innerHTML`/`insertAdjacentHTML`
- `lib/spm_cache/web/assets/log.js` — FOUND, `node --check` OK, zero `innerHTML`/`insertAdjacentHTML`
- `spec/web_frontend_spec.rb` — FOUND, 213 examples, 0 failures, 0 pending
- Commit `4dcda2b` — FOUND in `git log`
- Commit `c090c4c` — FOUND in `git log`
- Commit `aed6ed9` — FOUND in `git log`
- `bundle exec rspec` (full suite) — 1131 examples, 0 failures
- Live smoke test (real WEBrick boot via `spec/support/web_server_boot.rb`): `GET /` → 200, all four `/assets/*` → 200 with correct content types, `/api/state`/`/api/doctor`/`/api/graph`/`/api/runs` → 200 with real (non-fabricated) JSON payloads

One pre-existing, environment-only failure was observed and left untouched (out of scope, unrelated to this task): `spec/web_jobs_spec.rb`'s "adds no token-shaped variable" example fails only when the ambient `CLAUDE_CODE_MESSAGING_TOKEN` environment variable (set by the Claude Code harness this session ran inside) is present in the shell — verified by re-running with that one variable unset, which restores 1131/1131 green. This is not a product bug and is not caused by this task's changes.
