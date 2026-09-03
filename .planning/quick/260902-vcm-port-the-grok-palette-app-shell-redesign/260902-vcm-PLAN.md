---
phase: 260902-vcm-port-the-grok-palette-app-shell-redesign
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/spm_cache/web/assets/index.html
  - lib/spm_cache/web/assets/styles.css
  - lib/spm_cache/web/assets/app.js
  - lib/spm_cache/web/assets/log.js
  - spec/web_frontend_spec.rb
autonomous: true
requirements: [QUICK-GROK-SHELL-01]

estimate:
  tokens: 180000
  raw_tokens: 120000
  tasks: 3
  confidence: low

must_haves:
  truths:
    - "The served dashboard renders the Grok monochrome app-shell (topbar / alert-rail / nav-rail / 4 surfaces) with zero fabricated data on cold load — every value is either empty/placeholder or populated by a real fetch/stream."
    - "Every id app.js and log.js query via getElementById still resolves in the new markup; none were silently dropped or renamed."
    - "Clicking a nav-rail item (or pressing 1-4) shows exactly one of the four surfaces and hides the other three; Run Log stays the default-visible surface."
    - "All real functional behavior — token bootstrap, X-SPM-Token fetches, SSE streaming with Last-Event-ID resume, textContent-only rendering, build/rollback/toggle/apply/revert POST flows, cytoscape graph — is byte-identical in logic to before the port, only DOM targets moved."
    - "bundle exec rspec is fully green with spec/web_frontend_spec.rb updated to assert the NEW real structure, not weakened or skipped."
  artifacts:
    - lib/spm_cache/web/assets/index.html
    - lib/spm_cache/web/assets/styles.css
    - lib/spm_cache/web/assets/app.js
    - lib/spm_cache/web/assets/log.js
    - spec/web_frontend_spec.rb
  key_links:
    - "app.js/log.js getElementById(...) calls -> matching id attributes in the ported index.html"
    - "state/doctor/graph render functions -> #state-rows (tbody) / #check-list (ul) / #graph-wrap (default-visible) targets"
    - "nav-rail click + keydown handlers -> .surface[hidden] toggling, aria-current, localStorage persistence"
    - "spec/web_frontend_spec.rb assertions -> actual served bytes of the new files (no stale byte-pins against the old structure)"
---

<objective>
Port the Grok-palette app-shell redesign (topbar + alert-rail + left nav-rail + 4 switchable surfaces: Run Log / Cache State / Doctor / Dependency Graph) from the OpenDesign mockup into the real production frontend at `lib/spm_cache/web/assets/`, rewiring `app.js`/`log.js` to the new container ids per the redesign rationale doc's section 7 rewiring notes — while preserving 100% of the real fetch/token/SSE/toggle/build logic, the full DOM-id contract, and the security/offline posture. Update `spec/web_frontend_spec.rb` so its byte-level pins describe the NEW real structure instead of failing against it.

Purpose: the current single-scroll-column layout pushes 3 of 4 panels below the fold with no attention signal; the redesign fixes this with an app-shell (no page scroll, elastic log viewport, persistent nav, alert rail) using a validated Grok/xAI monochrome palette.
Output: production `index.html`/`styles.css`/`app.js`/`log.js` implementing the redesign with real data only, and a fully green `bundle exec rspec`.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@/Users/ddphuong/Projects/next-labs/spm-cache/lib/spm_cache/web/assets/index.html
@/Users/ddphuong/Projects/next-labs/spm-cache/lib/spm_cache/web/assets/styles.css
@/Users/ddphuong/Projects/next-labs/spm-cache/lib/spm_cache/web/assets/app.js
@/Users/ddphuong/Projects/next-labs/spm-cache/lib/spm_cache/web/assets/log.js
@/Users/ddphuong/Projects/next-labs/spm-cache/spec/web_frontend_spec.rb

Redesign source (read-only reference — do NOT copy demo.js or its mock data):
@/Users/ddphuong/Library/Application Support/Open Design/namespaces/release-stable/data/projects/spm-cache-web-dashboard-redesign-eb83/index.html
@/Users/ddphuong/Library/Application Support/Open Design/namespaces/release-stable/data/projects/spm-cache-web-dashboard-redesign-eb83/assets/styles.css
@/Users/ddphuong/Library/Application Support/Open Design/namespaces/release-stable/data/projects/spm-cache-web-dashboard-redesign-eb83/assets/demo.js
@/Users/ddphuong/Library/Application Support/Open Design/namespaces/release-stable/data/projects/spm-cache-web-dashboard-redesign-eb83/docs/redesign-rationale.md
@/Users/ddphuong/Library/Application Support/Open Design/namespaces/release-stable/data/projects/spm-cache-web-dashboard-redesign-eb83/reference/dom-contract.md

Design decisions locked for this port (made during planning, from live diffing the mockup against the real app.js/log.js source — apply these, do not re-litigate):

1. **Strip every OpenDesign/mockup-only artifact** from the ported `index.html`: `data-od-id="..."` attributes, the `<script src="assets/demo.js">` tag (replace with the real `cytoscape.min.js` + `type="module" app.js` + `type="module" log.js` trio, cytoscape first), the `<p class="graph-note">Static preview...</p>` line (the real app mounts real cytoscape — that sentence is a lie in production), and the favicon `<link rel="icon">` may be kept or dropped at your discretion (cosmetic, no functional coupling).
2. **Strip every hardcoded mock value** baked directly into the redesign's HTML (this dashboard must never show fabricated numbers before a real fetch resolves): the topbar `#topbar-state` "Running" state-pill, `#runstat-cmd` "spm-cache build", the whole package-count/elapsed progress meter (`#meter-fill`, `#runstat-count`, `#runstat-elapsed` — DELETE these three nodes and their `.meter`/`.runstat-num` wrapper entirely: there is no `packages_total`/`packages_done` field anywhere in the run-log JSONL event vocabulary (12-04 D-04, frozen) to back a real progress meter, and a live elapsed counter would require a client-side ticking clock, which log.js is explicitly forbidden from having, T-14-17 "no client clock" — do not invent either); the `<dl class="rail-facts">` block (Cache/Hit rate/Saved — none of these three numbers exist anywhere in the current wire contract or state payload; delete the whole block, it cannot be backed by real data without new server work, which is out of scope); the hardcoded `rail-badge-doctor`/`rail-badge-cache` glyphs/titles/counts (reset to a real cold-load default: hidden or empty, wired for real in Task 2); the 5 fake `<option>` entries inside `#log-runs` (reset to an empty `<select id="log-runs"></select>`, populated for real by log.js's existing `refreshRuns()`); every `#state-rows`/`#check-list` row (these already ship empty `<tbody>`/`<ul>` in the mockup source — keep them empty); the doctor `#doctor-summary` tally numbers ("1 failed", "2 warnings", "6 passed", "9 checks...") — reset to empty spans, wired for real in Task 2; all `stamp`/`port-label` spans — reset to empty (JS fills them); the `#log-card`'s hardcoded "Running"/"spm-cache build"/"--config Debug..."/timestamps/run-id — reset to neutral placeholder text (e.g. `Loading…` in the status slot, empty elsewhere), since section 7 of the rationale notes `#log-card` no longer starts `hidden` and must therefore hold real cold-load placeholder text instead.
3. **`#log-banner`, `#log-switch`, `#log-overlay`'s follow pill, and the filter pill move from JS-created-per-event to static markup-with-real-wiring.** The redesign gives static children (`#log-banner-text`, `#log-banner-jump`, `#log-switch-btn` inside `#log-switch`; `#log-follow-btn` inside `#log-overlay`; a standalone `#log-filter-pill` in a new `.log-toolbar` row above the viewport, OUTSIDE the overlay). Port these as static nodes and rewrite log.js's `showBanner`/`renderSwitchNotice`/`renderPill` to reuse the existing node (toggle `.hidden`, set `.textContent`, attach the click listener ONCE at boot) instead of creating/appending a new element on every call. `#log-filter-pill` ships in the mockup as a bare `<span>` — change it to `<button type="button" class="log-pill-btn log-filter-pill mono" id="log-filter-pill" hidden>` in the ported markup (keep both classes so it keeps the pinned `.log-pill-btn:focus-visible` ring) so it stays a real, keyboard-operable control, matching the existing pause pill's contract.
4. **`#state-sync-bar` moves from create/destroy-on-every-render to static show/hide.** The redesign ships it as a static, `hidden`-by-default node with static `#sync-revert`/`#sync-apply`/`#sync-message` children already in the DOM (not built by `buildSyncBar()`). Rewrite `renderState()`/`buildSyncBar` callers to toggle `.hidden` and patch text/labels on the existing static nodes instead of inserting/removing a built element every poll.
5. **New real functionality this port must add** (all backed by data already available in existing fetch responses or existing JS state — none of it is fabricated): nav-rail surface switching (click + `1`-`4` keydown + `/` focuses `#state-filter` + `Escape` blurs an input + persist the active surface in `localStorage`, ported from the redesign's own `showSurface()` in `demo.js` lines ~203-236, which is real DOM logic with zero mock data — do not port anything else from `demo.js`); `#state-filter` substring search + the 4 state chips (`all`/`hit`/`missed`/`other`) filtering the already-rendered `#state-rows`, `#chip-n-*` counts and `#state-total` derived from the real `data.packages` array, `#state-empty` shown when a filter yields zero visible rows; `#doctor-summary` tallies rendered from the real `envelope.data.summary` object already returned by `/api/doctor`; `#rail-badge-doctor` (glyph+title from `data.summary.failures`/`warnings`) and `#rail-badge-cache` (count from `data.packages.filter(p => p.pending).length`) — both real, already-fetched numbers; `#log-count` ("N lines") derived from log.js's existing `ringCount + evicted` counters.
6. **`#graph-wrap` no longer starts `hidden`** (rationale section 7). Keep a `.loading` placeholder as `graph-body`'s first child (matching the existing `removeLoading()`/`.loading` querySelector pattern already used for state/doctor) so the empty-graph and "no graph yet" paths still render honestly instead of an empty canvas flash; `renderGraph`'s existing `!data.present` branch still applies.
7. **Keep the real cytoscape integration untouched.** `cytoscape.min.js` stays vendored and referenced before `app.js`; do not port `demo.js`'s SVG/DOM stand-in graph renderer or its `GRAPH_NODES`/`GRAPH_EDGES` mock arrays.
8. **Preserve exactly:** dark-only (no light-mode branch), zero build step, zero CDN, offline-only, `X-SPM-Token` on every fetch, textContent-only rendering (never innerHTML — T-13-13/T-14-16), the `[hidden] { display: none !important; }` rule (rationale section 7 flags it load-bearing — several class rules set `display: flex` on elements toggled via `.hidden`, e.g. `#log-banner`, `#build-confirm`, `#state-sync-bar`, `#log-switch`, `#log-filter-pill`), and the existing keyboard-focus-visible ring pattern (extend it to any newly-static interactive node).
</context>

<tasks>

<task type="tracer">
  <name>Task 1: Port the app-shell HTML + Grok-palette CSS (structure only, real cold-load defaults)</name>
  <files>lib/spm_cache/web/assets/index.html, lib/spm_cache/web/assets/styles.css</files>
  <action>
    Replace `index.html` with the redesign's app-shell structure (topbar / alert-rail / nav-rail / `main.surface-main` holding the 4 `section.surface` elements: run/cache/doctor/graph, Run Log `is-active`/visible by default) — applying context decisions 1, 2, 3 (markup shape only — the log.js/app.js behavior rewiring for these is Tasks 2-3), 4 (markup shape only), 6, and 7 verbatim. Before finalizing, grep the CURRENT `app.js` and `log.js` for every `getElementById`/`byId(...)` call and confirm each of those ~40 ids exists somewhere in the new markup (cross-check against `reference/dom-contract.md`, but trust the live grep over the doc — the doc admits it "may not be 100% exhaustive"). Do not rename or drop any id the real JS queries.
    Replace `styles.css` wholesale with the redesign's stylesheet (it is a complete, self-contained sheet already on the Grok monochrome token set — a copy, not a rewrite), keeping the `[hidden] { display: none !important; }` rule and the `.log-filter-pill`/`.log-follow-btn` display:flex overrides that make the `.hidden` toggle pattern work for the newly-static nodes from decision 3/4. Do not reintroduce the old GitHub-dark blue `#2196F3` accent anywhere.
  </action>
  <verify>
    <automated>cd /Users/ddphuong/Projects/next-labs/spm-cache && ruby -e "h=File.read('lib/spm_cache/web/assets/index.html'); ids=%w[port-label conn-pill log-runs runs-slot build-controls ctl-build ctl-rebuild ctl-rollback ctl-message build-confirm ctl-cancel ctl-confirm log-body log-card log-status log-trigger log-command log-config log-started log-argv log-runid log-banner log-switch log-viewport log-overlay rail-phases rail-packages state-body state-stamp state-refresh sync-apply sync-message sync-revert doctor-body doctor-stamp doctor-run graph-body graph-stamp graph-refresh graph-wrap graph-legend cy-canvas]; missing=ids.reject{|i| h.include?(%(id=\"#{i}\"))}; raise \"MISSING: #{missing}\" unless missing.empty?; puts 'all ids present'"</automated>
    <human-check>Open the served page in a browser; confirm the app-shell layout renders (topbar, alert-rail collapsed to 0 height, left nav with Run Log active), no fabricated numbers are visible anywhere (topbar state pill, stamps, port label, log identity card, doctor tallies, log-runs dropdown all read empty/placeholder), and no console error about a missing script.</human-check>
  </verify>
  <done>index.html contains every id from the DOM-id contract with no fabricated content baked into the markup; styles.css is the redesign's Grok-palette sheet wholesale with `[hidden]` still `!important`; no `data-od-id`, `demo.js` reference, or "Static preview" note remains.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Rewire app.js — state/doctor/graph containers, nav-rail surface switching, cache filter/chips</name>
  <files>lib/spm_cache/web/assets/app.js</files>
  <behavior>
    - `renderState` writes rows into `byId('state-rows')` (a `<tbody>`) only — `<thead>` and the filter/chip toolbar are now static markup it must not touch.
    - `renderState`'s sync bar path toggles `byId('state-sync-bar').hidden` and patches `#sync-message` text in place, instead of calling a `buildSyncBar()` that constructs and inserts a new node every render (context decision 4).
    - A package-name substring typed into `#state-filter`, or a click on one of the 4 `#state-tools .chip` buttons, dims/hides non-matching rendered rows (CSS class toggle, never a DOM removal of data) and updates `#chip-n-all`/other chip counts and `#state-total` from the real `data.packages` array already held after the last successful `/api/state` fetch; `#state-empty` becomes visible only when the current filter matches zero rows.
    - `renderDoctor` writes check rows into `byId('check-list')` (a `<ul>`) and separately renders `byId('doctor-summary')`'s tallies from `envelope.data.summary` (ok/warnings/failures counts) — both real, no re-derivation from the checks array.
    - `loadGraph`/`renderGraph` no longer sets `graph-wrap.hidden = false` on success (it starts visible per Task 1); the `!data.present` branch still removes/keeps a `.loading` placeholder honestly instead of showing an empty canvas.
    - A new `showSurface(name)` function (ported from the redesign's real `demo.js` `showSurface`/keydown logic, zero mock data) toggles `.rail-item.is-active`/`aria-current` and `.surface.hidden` for exactly one of run/cache/doctor/graph, persists the choice to `localStorage`, and is wired to: each `.rail-item` click, digit keys `1`-`4` (ignored while an input/textarea/select has focus or a modifier key is held), `/` (preventDefault, switches to cache, focuses `#state-filter`), and `Escape` (blurs the focused input).
    - `#rail-badge-doctor` and `#rail-badge-cache` update from real numbers already available after each successful doctor/state fetch (`data.summary.failures`/`warnings`; `data.packages.filter(p => p.pending).length`) — never fabricated, never polled separately.
  </behavior>
  <action>
    Implement the behavior above by extending the existing `renderState`, `renderDoctor`, `renderGraph`/`loadGraph`, and `boot()` functions — do not rewrite the fetch/token/error-handling/poll-loop logic that already works, only its render targets and the new nav/filter glue described above. Read the redesign's `demo.js` lines ~203-236 (`showSurface`, the `railItems` click bindings, the `keydown` listener) as the reference for the switching mechanic only; do not port anything else from that file (no mock data, no `renderAttention`, no `pinBottom`). Keep every existing automated-test-proven behavior intact — this file must stay innerHTML-free and keep textContent-only rendering throughout.
  </action>
  <verify>
    <automated>cd /Users/ddphuong/Projects/next-labs/spm-cache && node --check lib/spm_cache/web/assets/app.js && grep -c "innerHTML\|insertAdjacentHTML" lib/spm_cache/web/assets/app.js | grep -qx 0 && echo "app.js syntax OK, zero innerHTML"</automated>
    <human-check>Boot the server, open the page: clicking each of the 4 rail items shows only that surface; pressing 1-4 does the same; typing in the cache filter narrows visible rows and updates chip counts; toggling a package checkbox still instant-persists; the unsaved-changes bar appears/disappears from the static node (no layout jump from insertion).</human-check>
  </verify>
  <done>state/doctor/graph render into the new static containers with zero regressions to fetch/poll/toggle/build logic; nav-rail switches surfaces via click, digits, and `/`; cache filter and doctor/cache rail badges show real derived numbers.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: Rewire log.js's static targets + topbar mirror, update spec/web_frontend_spec.rb, run full suite green</name>
  <files>lib/spm_cache/web/assets/log.js, spec/web_frontend_spec.rb</files>
  <behavior>
    - `showBanner` sets `byId('log-banner-text').textContent` and toggles `bannerEl.hidden`/class instead of `bannerEl.replaceChildren(...)`; the `#log-banner-jump` click listener is attached once (e.g. in `boot()`), not re-created per call.
    - `renderSwitchNotice` sets `byId('log-switch-btn').textContent/.title` and its click handler (via a persisted per-open listener, no duplicate bindings across calls) instead of `switchBar.replaceChildren(...)`.
    - `renderPill`'s "resume follow" pill patches the existing `byId('log-follow-btn')` (`.hidden`, `.textContent`) instead of creating `pauseBtn` via `el('button', ...)` and appending it to the overlay; same static-reuse treatment for `byId('log-filter-pill')` (created as a real `<button>` by Task 1).
    - `#log-card` starts un-hidden (Task 1) holding neutral placeholder text; `buildCard`/cold-load logic is adjusted so the placeholder is replaced by real data once `hello`/`run_start` arrives, never showing fabricated values in between.
    - `buildCard`/`setCardStatus` additionally mirror the derived status word/glyph into `byId('topbar-state')` and the command into `byId('runstat-cmd')` (same textContent, same derivation, two DOM targets) — no new data source, no client clock, no package-count/elapsed logic (those nodes were deleted in Task 1).
    - `#log-count` textContent is kept in sync with `ringCount + evicted` on every `appendLine`/`evictOldest` call ("N lines").
    - `spec/web_frontend_spec.rb` no longer asserts stale structure: every assertion tied to the OLD DOM (panel/panel-header/panel-body class names, `build-controls` living inside `log-body` before `log-card`, the old hardcoded GitHub-dark hex color table, the JS-creates-a-new-node-per-call assertions for banner/switch/pause pill/sync bar, the 3x `<p class="loading">Loading…</p>` static-paragraph pin) is rewritten to assert the NEW real structure and NEW Grok-palette token values (see the redesign rationale doc's palette table for the 12 exact new hex values) — coverage must not shrink: every mechanic the old spec proved (token bootstrap, X-SPM-Token, textContent-only, SSE reconnect, toggle poll-integrity, build/rollback/apply/revert flows, cytoscape single-instance, offline/CDN gates) keeps an equivalent assertion against the new structure.
  </behavior>
  <action>
    Implement the behavior above, keeping every existing fetch/EventSource/reconnect/ring-buffer/anchor-filter mechanic in log.js unchanged — only DOM query targets, insertion points, and the two new topbar-mirror lines change. Work through `spec/web_frontend_spec.rb` top to bottom (it is long — 1469 lines): for each `describe` block, decide whether the assertion is about DOM structure/CSS tokens (update to match the new real files) or about JS business logic that did not change (leave as-is; most `app.js`/`log.js` "source contract" assertions on fetch/render logic, copy strings, and prohibitions should still pass unmodified since only DOM targets moved). Then run the full suite and fix every remaining failure by correcting the ported source (never by weakening an assertion to dodge a real regression).
  </action>
  <verify>
    <automated>cd /Users/ddphuong/Projects/next-labs/spm-cache && bundle exec rspec spec/web_frontend_spec.rb && bundle exec rspec</automated>
    <human-check>Kick a real `spm-cache build` (or a synthetic run log) and watch the Run Log surface: the topbar state pill and command mirror the identity card's real status as it transitions running → success/failed; the follow/pause pill and filter pill still work from their new static nodes; a failed run's banner and jump-to-error button work with the static text target.</human-check>
  </verify>
  <done>log.js's banner/switch-notice/follow-pill/filter-pill logic operates on the new static nodes with identical behavior; the topbar state/command mirror shows only real derived data; `bundle exec rspec` is fully green with no skipped or pending examples and no assertion weakened relative to the pre-port spec's coverage.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|--------------|
| Browser DOM \<-\> untrusted subprocess/package text | Package names, doctor messages, log lines, run ids, argv all originate from `xcodebuild`/SPM/user-controlled `.spm-cache.yml` content and cross into the DOM via the render functions touched by this port |
| Browser \<-\> localhost server | Unchanged: same-origin, `X-SPM-Token` header, EventSource query-param token — this port does not touch the server side |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-QP-01 | Tampering | New `#state-filter` search + chip filtering (Task 2) | medium | mitigate | Filtering only toggles a CSS class on already-rendered, already-safe (textContent-built) row nodes — never re-renders untrusted text through a new code path; ban `innerHTML`/`insertAdjacentHTML` in this file is enforced by the existing spec assertions Task 3 must keep green |
| T-QP-02 | Tampering | Static banner/switch/pill nodes now patched via `.textContent` instead of `el()`-built nodes (Task 3) | medium | mitigate | `.textContent =` is the same XSS-safe sink `el()` used internally; no new `innerHTML` call is introduced — verified by the repo-wide `innerHTML`/`insertAdjacentHTML` grep in both app.js and log.js specs |
| T-QP-03 | Spoofing/Information Disclosure | Fabricated topbar metrics (package progress meter, elapsed clock, rail cache/hit-rate/saved stats) that the mockup hardcoded | high | mitigate | Deliberately deleted rather than wired with fake numbers (context decision 2) — no backing data exists in the current wire contract, so rendering them would show the user false operational state |
| T-QP-04 | Denial of Service (n/a — accepted) | No new npm/pip/cargo packages introduced by this port | low | accept | Pure asset port of already-vendored files; no new dependency, no package-legitimacy gate applies |
</threat_model>

<verification>
- `bundle exec rspec` passes with zero failures, zero pending, zero skipped.
- Manual load of the served page in a browser shows the app-shell with no fabricated numbers on cold load and a working nav rail.
- `grep -rn "innerHTML\|insertAdjacentHTML" lib/spm_cache/web/assets/*.js` returns nothing.
- `grep -n "data-od-id\|demo.js" lib/spm_cache/web/assets/index.html` returns nothing.
- `grep -n "#2196F3" lib/spm_cache/web/assets/styles.css` returns nothing (old blue accent fully replaced).
</verification>

<success_criteria>
The dashboard renders the Grok-palette app-shell in production, every DOM id app.js/log.js queries resolves, nav-rail surface switching works for real, all pre-existing real functional behavior (fetch/token/SSE/build/toggle/apply/revert/cytoscape) is unchanged, no fabricated data appears anywhere on cold load, and `bundle exec rspec` is fully green against an updated `spec/web_frontend_spec.rb` that describes the new real structure without any coverage regression.
</success_criteria>

<output>
Create `.planning/quick/260902-vcm-port-the-grok-palette-app-shell-redesign/260902-vcm-SUMMARY.md` when done.
</output>
