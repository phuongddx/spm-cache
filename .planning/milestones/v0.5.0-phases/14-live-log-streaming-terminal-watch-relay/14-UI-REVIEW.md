# Phase 14 — UI Review

**Audited:** 2026-09-01
**Baseline:** `14-UI-SPEC.md` (amended 2026-09-01 — completed-row `{relative}` carries its own ago)
**Screenshots:** not captured — no dev server detected on :3000/:5173/:8080 and this audit ran READ-ONLY (no servers permitted); code-only audit per the contract
**Surface:** `lib/spm_cache/web/assets/log.js` · `index.html` · `styles.css` (branch `gsd/v0.5.0-web-interface`, HEAD `008265b`)
**Browser evidence baseline:** D-14 probe (14-05-SUMMARY § D-14) — all 7 manual rows PASS in real headless Chromium, zero console errors, zero ≥400 responses; two probe-caught copy/status defects fixed and browser-re-verified (`207133d`, `3d2481a`). This review accepts that as the ground-truth baseline and audits the code against the written contract on top of it.

**Adversarial summary:** the implementation is contract-literate to an unusual degree — every pinned string is byte-exact, all five Prohibitions hold, the state matrix resolves line-for-line. The deductions below are real but none break a user task; nothing blocks the completed phase. Findings inform Phase 15/16 polish.

---

## Pillar Scores

| Pillar | Score | Key Finding |
|--------|-------|-------------|
| 1. Visual Hierarchy / Typography / Spacing | 3/4 | Two spacing-token divergences (card row gap 4px vs pinned 8px; switch notice missing the pinned 8px stack gap); type roles otherwise byte-on-contract |
| 2. Color / Contrast | 3/4 | White-on-accent pill labels measure ≈3.1:1 (AA fail); banner ✗ glyph ≈4.3:1 marginal; token discipline otherwise flawless |
| 3. Interaction Affordance | 3/4 | Native controls, never-dead jumps — but zero hover feedback on any custom control and re-render churn kills in-progress focus |
| 4. States Coverage | 3/4 | Matrix honored line-for-line incl. both probe fixes; one D-13 letter-divergence: tall live-run replay never engages follow |
| 5. Accessibility | 3/4 | Contract ARIA exact (`role="log"`, `aria-pressed`, `role="alert"`, focus rings) — keyboard focus destroyed by control re-creation |
| 6. Responsive | 2/4 | Zero media queries; fixed 200px rail + 480px viewport degenerate to ~6-character log lines at phone widths |

**Overall: 17/24**

**Findings by severity:** 0 BLOCKER · 5 WARNING · 7 MINOR · 2 INFO

---

## Top 3 Priority Fixes

1. **[W2] Cold load of a live run whose replay exceeds the viewport never engages follow** — the flagship flow (opening the dashboard mid-build) leaves the viewer at the top of history; the first streamed line raises `paused — 1 new lines` instead of tailing, contradicting D-13's "follow engages when the replay completes". The D-14 probe row 1 passed only because its replay fit the 480px viewport (~28 lines). Fix spec-first (project style): either amend D-13 to the implemented read-and-pause posture, or set `follow = true` on the hello live-run branch (`resetForRun(payload.run, true)`, log.js:609-627) and let D-01's upward-scroll disengage own the reading case — observably equivalent to "follow at completion" since replay appends then stick to the growing tail.
2. **[W1] White text on accent fill fails WCAG AA on every accent control** — `#FFFFFF` on `#2196F3` is ≈3.1:1 (needs 4.5:1 at 12px/400). Hits the follow-tail pill, filter pill, `Jump to first error`, and the switch-notice run-id control (`.log-pill-btn`, styles.css:583-596; inherited from 13's `.btn`). Fix: `color: #0D1117` on the accent fill (≈6.1:1, passes) — one declaration on the shared rule — or darken the fill.
3. **[W3] Keyboard focus is destroyed by control re-creation** — `renderPill` (`overlay.replaceChildren()`, log.js:201-202) rebuilds the pause/filter pills on *every* queued line while paused; `renderChips` (log.js:484-487) removes and recreates every chip on each new anchor and on every filter change. A keyboard user tabbing to the pill — or filtering via a chip — loses focus mid-interaction as the focused node is discarded; during a live build the rail rebuilds per anchor event. Fix: keep persistent button nodes, toggle `hidden`, patch `textContent`; re-append only when the chip set actually changes.

---

## Detailed Findings

### Pillar 1: Visual Hierarchy / Typography / Spacing (3/4)

**Hierarchy — pass.** Run Log renders first per A1 (index.html:19-58, comment-cited); the 480px terminal viewport is the unambiguous focal point; panel header is title-left/controls-right; no icon-only controls exist; row-1 card items outrank muted Label-size meta rows. Empty-state `h3` inside the viewport nests correctly under the panel `h2`.

**Typography — pass, byte-on-contract.** Exactly the four pinned roles appear (20/600 title, 16/600 panel headings, 14 body incl. banner text and card status, 12 Label for every log line, chip, pill, dropdown entry, meta row — all mono where the contract demands). Exactly two weights (400/600: `.log-command` 600 per D-06, `.log-banner-glyph`/`.check-marker` 600). No italics, no `text-transform`, no third size anywhere in the 660-line sheet.

**Spacing — two contract divergences:**
- **[W5] Switch-notice bar has no gap before the stream row.** The spec's spacing table pins `sm` (8px) for "gaps between banner/notice/stream stack"; only `.log-banner` carries `margin-bottom: var(--space-sm)` (styles.css:449-455). `.log-switch` (styles.css:640-645) has no bottom margin and `.log-stream-row` no top margin, so after a switch the notice text sits flush against the stream border. Fix: `margin-bottom: var(--space-sm)` on `.log-switch`.
- **[M1] Identity-card internal row gap is `xs` (4px); the contract pins `sm` (8px)** ("identity-card internal row gap" row of the spacing table). `.log-card` (styles.css:391-398) uses `gap: var(--space-xs)`. One-token fix; visual impact is density-only.

All other geometry verified on-token: card `sm` padding + `xl` (32px) break before the stream group ✓; banner/overlay insets `xs` ✓; stream-row and overlay pill gaps `sm` ✓; panel padding `md`, header margin `lg`, topbar `2xl`, page margin `3xl` ✓.

### Pillar 2: Color / Contrast (3/4)

**Token discipline — exemplary.** Zero new colors; every Phase 14 rule references `var(--c-*)`. The rgba fills are the sanctioned 10%-alpha badge pattern and match their tokens exactly (`rgba(244,67,54,.1)`=fail, `rgba(255,152,0,.1)`=warn, `rgba(33,150,243,.1)`=accent, `rgba(158,158,158,.1)`=neutral, `rgba(63,81,181,.1)`=plugin). Accent inventory: 7 unique surfaces (follow pill, filter pill, jump button, run-id control, connected pill text, running status, active chip) — inside the 10% budget and exactly A3's controls-and-liveness family; verdict glyphs never take accent (`.log-ok/.log-warn/.log-fail` only). Connecting pill is `--c-neutral` (#9E9E9E), not muted, per the single-owner rule ✓.

**Contrast (WCAG math on the actual fills):**

| Pair | Ratio | Verdict |
|------|-------|---------|
| `#E6EDF3` on `#0D1117` viewport | ≈16.0:1 | pass |
| `#8B949E` muted on `#0D1117` / `#161B22` | ≈6.2 / 5.6:1 | pass |
| `#2196F3` accent text on `#161B22` | ≈5.5:1 | pass |
| `#2196F3` on its 10% fill (active chip) | ≈4.9:1 | pass |
| `#FF9800` on panel / warn fill | ≈8.0 / 6.8:1 | pass |
| `#F44336` on `#161B22` (err lines, card word) | ≈4.7:1 | pass (thin) |
| **`#FFFFFF` on `#2196F3` (all accent-fill controls)** | **≈3.1:1** | **[W1] AA fail** |
| `#F44336` ✗ glyph on fail 10% banner fill | ≈4.3:1 | **[M2] marginal fail** |

- **[W1]** `.log-pill-btn` (styles.css:583-596) renders 12px/400 white labels on accent: follow pill, filter pill, jump button, run-id control — all fail 4.5:1. The spec's accessibility claim "all pinned color/text pairs meet 4.5:1" does not hold for this inherited pair. Concrete fix: `color: #0D1117` on `.log-pill-btn`/`.btn` (≈6.1:1 on accent).
- **[M2]** The banner's `✗` glyph (600 weight, 14px) on `rgba(244,67,54,.1)` over panel measures ≈4.3:1. Mitigated: the banner *text* is primary at ≈13.4:1 and the state is word-encoded in the card — severity minor, but the pair misses the contract's own 4.5:1 pin.

### Pillar 3: Interaction Affordance (3/4)

**Pass:** every control is a native `<button type="button">`/`<select>` (verified at every `el('button', …)` site — no submit leaks); dropdown label bound via `for`/`id`; cursor pointers on chip/pill/select; jump chains are never dead (first error → final line → oldest retained → top of viewport, log.js:434-459; anchor target → oldest retained, log.js:540-547); clicking the active chip clears with the view staying put; the pause pill appears only when lines are genuinely queued and never mid-replay; bottom-riding re-engages follow automatically (log.js:374-389); the banner has no dismiss, per contract.

- **[W3]** Focus churn — see Top 3. Worst case: keyboard user activates a chip to filter → `renderChips` recreates all chips → focus falls to `<body>`, tab order restarts; repeats on every anchor arrival during a live build.
- **[M3]** No `:hover` feedback on `.log-chip` (styles.css:527), `.log-pill-btn` (583), or `.log-runs-select` (615) — custom backgrounds suppress the native button affordance, so the rail and pills give no pointer-responsive signal. Fix: slight border/lightening on hover.
- **[M4]** Pill click targets are ≈25px tall (`xs`/`sm` padding on 12px text) — below the 44px touch guideline; acceptable for a desktop dev tool, worth revisiting if 15/16 touch this surface.
- **[I2]** By design: the overlay pill row (styles.css:571-579) intercepts clicks on the viewport's bottom strip while pills show — pinned geometry per the spec's Overlay row.

### Pillar 4: States Coverage (3/4)

**Matrix walk — 31/31 covered categories verified in code:** empty (viewport `No runs yet` + accent `.cmd` display-only span, log.js:288-295; card hidden; rail labels-only; dropdown single disabled `No runs yet`) · loading (muted `Loading…` para before hello; `● connecting…` pill; dropdown `Loading…` entry) · error (CLOSED → locked token-invalid page replacement, log.js:158-165; transient → `↻ reconnecting…` with lines kept; CP14 → `! interrupted — exit unknown` incl. the `3d2481a` both-spellings map, log.js:300-306; dropdown `Couldn't load the run list: {message}. Reload the page to retry.` with last-good list retained, log.js:705-709) · populated (all card rows, dividers `── {name} ──`, `✗ `-prefixed err lines, run_start/run_end/package_end/sh render no line, unknown keys ignored) · partial (`Config —`, `· credentials redacted`, missing run_end never derives completion) · overflow (500-line ring, live elision counter, error/anchor eviction degradation to the oldest retained line — never a dead control) · long-text (ellipsis+`title` on argv, run id, chips, filter pill at 240px, switch run-id).

**Copy audit: all 20+ pinned strings byte-exact** against the COPY table (log.js:34-54) — panel title, three pill states, token-invalid sentence, `paused — {N} new lines · jump to live`, elision, both banner templates, switch notice (with the no-previous-run suppression, log.js:676-680), `filtered: {name}`, dropdown entry + ` · viewing`, empty state, runs-error, `! {message}`, `{N} min/hr ago` vocabulary over server stamps only (no `Date.now()` anywhere). **[M7]** `paused — 1 new lines` is ungrammatical at N=1 but byte-exact per the locked template — spec-owned, listed for a Phase 15 copy decision, not an implementation defect. **[M5]** Minor edge: `renderRunsOptions` sets `runsSelect.value = currentRun`; a pinned run absent from the 10 newest entries leaves the closed select blank.

- **[W2]** The one divergence — D-13 live-run cold load, see Top 3. `appendLine`'s completion gate (`replaying && atBottom()`, log.js:381) only flips replaying when the whole file fits; a live run with >~28 lines of history ends replay above the bottom, follow never engages, and the first streamed line starts the paused counter. Completed-run cold load (follow off) is correct per D-13 branch 2 — only the live branch diverges.

### Pillar 5: Accessibility (3/4)

**Contract-exact:** `role="log"` + `aria-live="off"` + `aria-label="Run output"` + `tabindex="0"` viewport (index.html:40); `aria-live="polite"` on card status and connection pill; `role="alert"` banner (class-swap in `showBanner` preserves the attribute); `aria-pressed` set on every chip both ways (log.js:488-497); `:focus-visible` accent ring on pills, chips, and select (styles.css:598-603); pill accessible names are their full visible labels; glyph+word pairs everywhere (no color-only status; the filter dim state also has the `filtered:` pill and `aria-pressed` chip as non-color indicators); no animations anywhere (instant `scrollTop` — also satisfies prefers-reduced-motion trivially); `label for` on the select; asset ref `assets/log.js` (index.html:102) per Prohibition 1; textContent-only rendering (Prohibition 2 — grep-clean of `innerHTML`/`insertAdjacentHTML`/`document.write`/`outerHTML`).

- **[W3]** Focus destruction on re-rendered controls — the pillar's deduction; see Top 3.
- **[M6]** Full argv/run-id/chip values are reachable only via `title` (hover); keyboard users get the tooltip-less ellipsis. Standard platform limitation; noted for completeness.

### Pillar 6: Responsive (2/4)

**No responsive strategy exists** — zero `@media` in the 660-line sheet (13 shipped none; 14 inherited that). The spec declares no breakpoints either, so nothing is *contract*-violated — but the ticket asks for narrow-width behavior, and the fixed dimensions degenerate hard:

- **[W4]** `.log-rail` is `flex: none; width: 200px` (styles.css:506-511) beside a `flex: 1` column. At 375px: 375 − 48 (page padding) − 34 (panel chrome) − 208 (rail+gap) ≈ **85px of log viewport ≈ 6 monospace characters per line** — the primary surface is unreadable, and the rail is 200px of the 293px panel. At 768px it's workable (~40 chars). Fix: one `@media (max-width: ~800px)` rule stacking the rail below the viewport full-width (chips reflow into a wrapped row); the overlay row also needs `flex-wrap: wrap` (two pills + a long `paused — …` label overflow the 85px column today, styles.css:571-579), and `.panel-actions` (pill + `Recent runs` label + select ≈ 320px minimum) needs wrap allowance before the header overflows under ~640px.
- Banner (`flex-wrap`), switch notice (`flex-wrap`), and card main row (`flex-wrap`, styles.css:399-406) all degrade gracefully — the wrap discipline that exists is applied exactly where the contract pinned it.

---

## Prohibitions Verification (all five hold)

1. No framework/build/CDN/scheme-absolute URLs; new asset referenced as `assets/log.js` ✓ (index.html:102)
2. No `innerHTML`/`insertAdjacentHTML`/`document.write`/`outerHTML` — every dynamic string through `el()`/`textContent` ✓ (grep-clean)
3. No color-only status encoding ✓ (glyph+word pairs; dim backed by pill text + `aria-pressed`)
4. No stream animation — instant scroll positioning, no `transition`/`animation`/`scroll-behavior` in the sheet ✓
5. No client clock — `serverNowTs` from hello/`/api/runs` `now` stamps only; no `Date.now()` ✓

## Registry Safety

Skipped per its own gate: no `components.json` in the repo, and 14-UI-SPEC's Registry Safety table declares no third-party registries. Nothing to audit.

---

## Files Audited

- `lib/spm_cache/web/assets/log.js` (828 lines, full)
- `lib/spm_cache/web/assets/styles.css` (660 lines, full)
- `lib/spm_cache/web/assets/index.html` (104 lines, full)
- `.planning/phases/14-live-log-streaming-terminal-watch-relay/14-UI-SPEC.md` (contract baseline)
- `.planning/phases/14-live-log-streaming-terminal-watch-relay/14-05-SUMMARY.md` (D-14 probe baseline, § D-14)

**Recommendation count:** 3 priority fixes · 5 warnings · 7 minor · 2 informational. Advisory only — nothing here blocks Phase 14; items W1/W3/W5/M1 are one-line fixes worth folding into Phase 15's first touch of this surface, W2 wants a spec-first decision, W4 a breakpoint decision.
