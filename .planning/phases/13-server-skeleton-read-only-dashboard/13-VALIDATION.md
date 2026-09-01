---
phase: "13"
slug: "server-skeleton-read-only-dashboard"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-09-01"
---

# Phase 13 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | RSpec 3.12 (existing suite, hermetic; suite grows by ~100 examples across 10 new spec files this phase) |
| **Config file** | `spec/spec_helper.rb` (per-file default-deny `Core::Sh` guards per repo convention) |
| **Quick run command** | `bundle exec rspec spec/web_server_spec.rb` (Wave 0 names the real files below) |
| **Full suite command** | `bundle exec rspec` |
| **Socket policy** | CP7 discipline: exactly ONE port-0 integration spec (`spec/web_integration_spec.rb`) + the signal-subprocess pair (`spec/web_signals_spec.rb`); all other specs are StringIO/tmpdir-hermetic |
| **Estimated runtime** | ~45–75 s full suite (integration + signals files add ~20–30 s) |

---

## Sampling Rate

- **After every task commit:** Run quick command (the task's own spec files)
- **After every plan wave:** Run `bundle exec rspec`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 60 s (excluding the two real-process files, which run in the wave-level full-suite pass)

---

## ROADMAP Success-Criterion → Verification Map

| SC | Statement (abbreviated) | Automated evidence | Manual-only evidence |
|----|--------------------------|--------------------|----------------------|
| SC1 / WEB-01 | 127.0.0.1 bind, probe past occupied ports skipping AirPlay 5000/7000, opens browser | `spec/web_server_spec.rb` (bind + port:0), `spec/web_lifecycle_spec.rb` (skip-list probing, `--no-open`, open-after-ready ordering) | Real launch: `spm-cache web` opens the default browser at the printed URL |
| SC2 / WEB-02 | Live-instance reuse via marker + pid-liveness; no error, no second server | `spec/web_lifecycle_spec.rb` (live reuse / dead-pid heal / malformed marker), `spec/web_signals_spec.rb` (SIGKILL leaves stale marker that reads dead) | Second terminal launch prints "already running" URL + opens browser |
| SC3 / WEB-03 | SIGTERM/SIGINT → cleanup, exit 0 | `spec/web_signals_spec.rb` (real subprocess, TERM + INT, marker removed, exit 0) | Real-TTY Ctrl-C on a foreground `spm-cache web` |
| SC3 / WEB-04 | Invalid Host/Origin or missing token rejected on every route; fully offline assets | `spec/web_middleware_spec.rb` (predicate matrix), `spec/web_integration_spec.rb` (25-cell route × auth matrix + drive-by trio), `spec/web_frontend_spec.rb` (offline gate), `spec/web_packaging_spec.rb` (assets ship in gem) | True-offline load: disconnect network, hard-reload the dashboard |
| SC4 / DASH-01 | Cache-state table: size, cached/source, fidelity — re-derived from CLI's files | `spec/web_state_spec.rb` (join, sizes, freshness re-read), `spec/command_cache_list_spec.rb` (shared Inventory, output unchanged), `spec/web_frontend_spec.rb` (table copy/column pins) | Browser walkthrough: table renders with badges per UI-SPEC on a real project |
| SC5 / DASH-02 | Doctor on-demand from the registry, statuses + fix hints, cached with timestamp | `spec/web_doctor_spec.rb` (registry-driven stub check, has_run/run semantics, cached generated_at), `spec/doctor_spec.rb` (shared payload) | Browser walkthrough: Run Doctor → "Running…" → rows with ✓/!/✗ + ↳ hints + summary + "Cached — generated at" |
| SC5 / DASH-03 | Graph nodes via vendored cytoscape; affordance when graph.json absent | `spec/web_graph_spec.rb` (present flag, nodes, mtime stamp, error envelope), `spec/web_frontend_spec.rb` (vendored version comment, diamond/macro pins, empty-state copy) | Browser walkthrough: graph renders with legend; empty state names `spm-cache use` |

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 13-01-T1 | 01 | 1 | WEB-04, DASH-03 | T-13-01..03, 06, 07 | Host/Origin allowlists; fixed-time token compare; AccessLog off; X-Frame-Options | unit + one-boot integration | `bundle exec rspec spec/web_middleware_spec.rb spec/web_server_spec.rb` | ❌ Wave 0 (RED step creates them) | ⬜ pending |
| 13-01-T2 | 01 | 1 | WEB-01, WEB-02 | T-13-03, T-13-05 | 0600 atomic marker; symlink read-reject; bare URL only | unit (injected server double) | `bundle exec rspec spec/web_lifecycle_spec.rb` | ❌ Wave 0 (RED step) | ⬜ pending |
| 13-01-T3 | 01 | 1 | WEB-03, WEB-04 | T-13-04 | traversal-proof assets; Host-gated asset route | unit + real-subprocess signals | `bundle exec rspec spec/web_assets_spec.rb spec/web_signals_spec.rb` | ❌ Wave 0 (RED step) | ⬜ pending |
| 13-02-T1 | 02 | 2 | DASH-01 | T-13-11 (freshness) | shared single scan; Integer coercion | unit | `bundle exec rspec spec/command_cache_list_spec.rb spec/config_spec.rb` | ✅ exists (extend) | ⬜ pending |
| 13-02-T2 | 02 | 2 | DASH-01, DASH-03 | T-13-09, T-13-11 | token-gated routes; per-request re-reads | unit + boot envelope | `bundle exec rspec spec/web_state_spec.rb spec/web_graph_spec.rb` | ❌ Wave 0 (RED step) | ⬜ pending |
| 13-02-T3 | 02 | 2 | DASH-02 | T-13-10, T-13-12 | registry-only check source; Mutex cache swap; honest stamp | unit (hermetic Sh stubs) | `bundle exec rspec spec/web_doctor_spec.rb spec/doctor_spec.rb` | ❌ Wave 0 (RED) / ✅ doctor_spec extends | ⬜ pending |
| 13-03-T1 | 03 | 2 | WEB-04 | T-13-14 | committed vendored cytoscape; offline gate; UI-SPEC tokens | served-bytes pins | `bundle exec rspec spec/web_frontend_spec.rb` | ❌ Wave 0 (RED step) | ⬜ pending |
| 13-03-T2 | 03 | 2 | WEB-04, DASH-01 | T-13-13, T-13-15, T-13-16 | textContent-only DOM; token never in DOM; stamps from server time | served-source pins | `bundle exec rspec spec/web_frontend_spec.rb` | ✅ (created by 13-03-T1) | ⬜ pending |
| 13-03-T3 | 03 | 2 | DASH-02, DASH-03 | T-13-13 | fix-hint/markers verbatim; no node click handlers | served-source pins | `bundle exec rspec spec/web_frontend_spec.rb` | ✅ (created by 13-03-T1) | ⬜ pending |
| 13-04-T1 | 04 | 3 | WEB-04 | T-13-17, T-13-18 | 25-cell matrix + drive-by trio | one-boot integration (the CP7-sanctioned file) | `bundle exec rspec spec/web_integration_spec.rb` | ❌ Wave 0 (this task) | ⬜ pending |
| 13-04-T2 | 04 | 3 | WEB-04 | T-13-19 | gemspec ships assets; webrick window pinned | packaging pins | `bundle exec rspec spec/web_packaging_spec.rb` | ❌ Wave 0 (this task) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

*(Map filled by planner 2026-09-01. Wave 0 = RED steps inside each TDD task author its spec file; no external scaffold tasks needed.)*

---

## Wave 0 Requirements

- [x] Spec files named by the planner and created RED-first inside their tasks: spec/web_middleware_spec.rb + spec/web_server_spec.rb (13-01-T1); spec/web_lifecycle_spec.rb (13-01-T2); spec/web_assets_spec.rb + spec/web_signals_spec.rb (13-01-T3); spec/web_state_spec.rb + spec/web_graph_spec.rb + spec/web_doctor_spec.rb (13-02); spec/web_frontend_spec.rb (13-03); spec/web_integration_spec.rb + spec/web_packaging_spec.rb (13-04)
- [x] Fixtures: tmpdir projects via `Core::Config.instance.configure` + `reset!` (config_spec precedent); fixture graph.json/cache dirs per 13-02 behavior bullets; default-deny `Core::Sh` guards per file (doctor_spec.rb:61-67 pattern); boot helper defined once in spec/web_server_spec.rb and reused
- [x] `bundle install` after the 13-01-T1 gemspec webrick addition (precondition of every later web spec)

---

## Manual-Only Verifications

> The repo has no JS runtime and the suite is hermetic — browser behavior, real-TTY signals, and true-offline loading are verified by hand. Automated specs pin the served bytes and the server contracts; these items verify behavior and visuals.

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Browser auto-open on fresh start | WEB-01 | Real default-browser `open` + human-observable launch | Run `spm-cache web` in a real project; the default browser opens at the printed `http://127.0.0.1:{port}` and the dashboard renders |
| Token bootstrap URL cleanup | WEB-04 / UI-SPEC | Address-bar observation after history.replaceState | After load, the address bar shows `/` (no `?token=`); reload works (server re-redirects); the token never appears in the rendered page |
| Full dashboard walkthrough (3 panels) | DASH-01/02/03 + UI-SPEC | Visual verification of colors/spacing/copy/cytoscape render against the approved UI-SPEC; no JS-executing test infra | With a real cached project: state table (sizes, badges, ◆ macros), Run Doctor (Running… → ✓/!/✗ rows + ↳ hints + summary + Cached stamp), graph (node colors, diamond macros, legend); empty states on a fresh project (all three exact copy strings) |
| Auto-poll + error resilience | DASH-01 / UI-SPEC | Live polling observation | Leave the tab open ≥ 15 s: "Updated … · auto-refresh 5s" stamp advances; kill the server: error copy appears, last rows retained, loop resumes if the server returns |
| True offline load | WEB-04 | Network-level isolation | Disconnect the machine from the network; hard-reload the dashboard — everything renders (all assets local; zero console errors about blocked requests) |
| Real-TTY Ctrl-C exit | WEB-03 | Real terminal signal semantics (automated SIGTERM/SIGINT specs cover the mechanism) | Ctrl-C the foreground `spm-cache web`; it exits 0 promptly; `.spm-cache/web/server.json` is gone |
| Live-instance reuse UX | WEB-02 | Two-terminal human flow | While a server runs, launch `spm-cache web` again: "already running" message + browser opens; no port change, no second process |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60 s
- [ ] `nyquist_compliant: true` set in frontmatter
- [ ] Manual-only table executed and recorded (7 items above)

**Approval:** pending
