---
phase: "13"
slug: "server-skeleton-read-only-dashboard"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-09-01"
---

# Phase 13 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| browser / any web page → 127.0.0.1:PORT | untrusted: any page on the internet can issue requests to localhost (drive-by GET/POST, DNS-rebinding re-hosts) — localhost is NOT a trust boundary (research CP13) | Request bytes (Host/Origin headers, path, token) cross into the router gate before any auth'd code runs |
| local multi-user → marker / boot lock | semi-trusted: other local users cannot read 0600 but can pre-plant files/symlinks in project-adjacent dirs they control | Marker file writes/reads; `.boot.lock` flock |
| project/cache files → read models → HTTP | data authored by build tooling (graph.json, sidecars, yml) crosses into responses consumed by the browser — a hostile repo can plant hostile strings in module names/messages | Untrusted project-authored strings (rendered inert by 13-03's DOM contract) |
| WEBrick request threads → shared doctor cache | concurrent reads/writes of the one mutable server-side cache | {data, generated_at} pair under a Mutex |
| project-authored strings → DOM; vendored cytoscape → page execution | a hostile repository can plant HTML/script text in graph.json-derived fields — the browser must treat every dynamic string as inert text; third-party code executes in the dashboard origin (supply-chain surface) | Package names, check messages, fix hints; cytoscape.min.js bytes |
| released gem tarball → user machine | what ships in spec.files is what users run — a dropped asset or missing dependency is a shipping-integrity issue, not just a bug; the matrix spec is the phase's security assertion of record — weakening it to pass would silently reopen CP13 | spec.files glob; served bytes observed by the spec |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-13-01 | Spoofing (drive-by CSRF GET/POST) | Web::Middleware / Web::Router | high | mitigate | Origin-present-and-mismatch → 403: exact `http://127.0.0.1\|localhost:port` membership (`middleware.rb:32-36`, gate at `router.rb:65`); token (X-SPM-Token or ?token) required on ALL /api/* → 401 (`router.rb:121-125`, `router.rb:150-154`); single catch-all servlet makes the gate structural (`server.rb:45`); 25-cell matrix `web_integration_spec.rb:71-123` | closed |
| T-13-02 | Spoofing (DNS rebinding) | Web::Middleware allowed_host? | high | mitigate | Host allowlist `LOOPBACK_HOSTS` exact `host:port` on the BOUND port, host case-insensitive, port exact, nil/missing rejected (`middleware.rb:13`, `middleware.rb:19-26`); applied before dispatch on EVERY route incl. assets (`router.rb:64`); spoofed_host matrix row + second-allowlist-entry spec `web_integration_spec.rb:243-246` | closed |
| T-13-03 | Information disclosure (token leakage) | WEBrick access log / marker / stdout | high | mitigate | `AccessLog: []` with rationale (`server.rb:29-33`); marker 0600 chmod-BEFORE-rename (`marker.rb:52-53`); stdout prints bare URL only (`command/web.rb:69`, `command/web.rb:126`); bootstrap 302 is the sole token delivery (`router.rb:182-184`); `Cache-Control: no-store` on every response (`router.rb:179`); dev `.gitignore` `.spm-cache/` entry; web verb excluded from run logs (`core/run_log.rb:103`); WR-01 error envelopes keep WEBrick from logging escapes at ERROR level | closed |
| T-13-04 | Tampering (path traversal via asset routes) | Web::Assets | high | mitigate | basename-only validation — rejects separators, backslash, `..`, leading dot, NUL (`assets.rb:61-68`); `expand_path` + `start_with?("#{@root}/")` containment + `File.file?` (`assets.rb:37-42`); 404 on any miss (`router.rb:110-113`); decode-then-validate against WEBrick's percent-decoded path (`router.rb:76-80`); encoded forms proven end-to-end in the matrix | closed |
| T-13-05 | Tampering (marker-file symlink swap) | Web::Marker | medium | mitigate | read rejects symlinks via `File.lstat` (`marker.rb:26-28`); write via Tempfile-in-marker-dir + `File.rename` (replaces the directory entry, never writes through a pre-planted symlink) (`marker.rb:43`, `marker.rb:53`); 0600 after write (`marker.rb:52`) | closed |
| T-13-06 | Side-channel (timing on token compare) | Web::Middleware valid_token? | low | mitigate | SHA256-digest both sides (equalizes length) then XOR-fold accumulate with a single zero check — never `==` on the raw token, no length short-circuit (`middleware.rb:46-49`, `middleware.rb:62-65`); wrong-length full-compare pin `web_middleware_spec.rb:79-82` | closed |
| T-13-07 | Tampering (clickjacking / iframe embedding) | Web::Router | low | mitigate | `X-Frame-Options: DENY` set first in `service` — every response, rejection or payload alike (`router.rb:56`, `router.rb:177-180`); header sweep `web_integration_spec.rb:226-240` | closed |
| T-13-08 | DoS (port-probe exhaustion / request flood) | Web::PortProber / WEBrick threads | low | accept | bounded 25-attempt probe with clear GeneralError on exhaustion (`port_prober.rb:11-12`, `port_prober.rb:30-33`); localhost dev tool — WEBrick per-request threads acceptable at dev-tool request rates | closed (accepted) |
| T-13-09 | Information disclosure (project metadata via /api/*) | Web::ReadModels::* + Router | high | mitigate | every /api/* arm token-gated — state/graph via `api_read` (`router.rb:121-125`), doctor via `api_doctor` (`router.rb:150-154`); dispatch admits no other route shape (`router.rb:74-88`); 25-cell matrix re-proves per endpoint | closed |
| T-13-10 | Tampering (torn concurrent doctor cache) | Web::ReadModels::Doctor | low | mitigate | Mutex around the {data, generated_at} swap — data and stamp move as ONE pair (`doctor.rb:32`, `doctor.rb:64-65`), reads under the same lock (`doctor.rb:42`); proven by the thread-pair spec | closed |
| T-13-11 | Information disclosure (stale data presented as fresh) | State/Graph read models | medium | mitigate | stateless class-level callables re-reading disk on EVERY call, zero memoization (`read_models/state.rb:13-16`, `read_models/graph.rb:12-20`); graph stamp = `File.mtime` server-side truth (`graph.rb:18`); doctor cache's own generated_at passed through the envelope verbatim, never re-stamped (`router.rb:161-166`) | closed |
| T-13-12 | DoS (doctor checks shell out synchronously per request) | Web::ReadModels::Doctor | low | mitigate | `run:true` is the ONLY path executing checks; cache serves repeats (`doctor.rb:39-42`); Run Doctor button disables itself while in flight (`app.js:208-209`) | closed |
| T-13-13 | Tampering (stored XSS via module names / messages / fix hints) | app.js DOM helpers | high | mitigate | zero `innerHTML`/`outerHTML`/`insertAdjacentHTML`/`document.write`/`eval`/`new Function` in app.js (audit grep: 0 matches); every dynamic string through `el()`/`textContent` (`app.js:3-5`, `app.js:23-28`); spec pins `web_frontend_spec.rb:219-223`; browser walkthrough double-checked markup-looking fixtures (13-UAT) | closed |
| T-13-14 | Tampering (supply-chain: substituted/CDN cytoscape) | assets/cytoscape.min.js | medium | mitigate | committed vendored dist served locally, never fetched at runtime — first line `/*! cytoscape v3.34.2 — MIT …` (no scheme URL) and 435,643 bytes > 300 KB structural pins (audit stat); offline byte-greps for first-party assets + structural-only cytoscape pins (`web_frontend_spec.rb:87-100`, `web_packaging_spec.rb:111-121`); ships inside the gem via the gemspec glob (`spm_cache.gemspec:13-15`) + real gem-build smoke (`web_packaging_spec.rb:69-95`) | closed |
| T-13-15 | Information disclosure (token in DOM/Referer) | app.js token bootstrap | medium | mitigate | token → sessionStorage → `replaceState('/')` BEFORE first render (`app.js:16-19`); X-SPM-Token header on every request (spec pin `web_frontend_spec.rb:114-116`); token never written into the DOM (`web_frontend_spec.rb:118-121`); server `no-store` (`router.rb:179`); headless-Chromium re-verification: URL cleaned to '/', token absent from DOM | closed |
| T-13-16 | Spoofing (stale panel presented as current) | app.js stamps | low | mitigate | every stamp derives from SERVER timestamps — envelope `generated_at` (`app.js:133-134`, `app.js:182-183`) / `graph_generated_at` (`app.js:266-267`); `Date.now()` absent from app.js (audit grep: 0 matches; spec pin `web_frontend_spec.rb:209-212`); failed polls keep last-good rows beside the error copy | closed |
| T-13-17 | Tampering (regression of the auth gate before Phase 15 POSTs) | spec/web_integration_spec.rb | high | mitigate | exhaustive 25-cell route × case matrix with self-naming rows (`web_integration_spec.rb:71-123`) — any middleware/router change that opens a cell fails the suite by name; the gate Phase 15 inherits | closed |
| T-13-18 | Tampering (drive-by POST/GET variants not covered) | middleware matrix cases | medium | mitigate | explicit rows on EVERY /api/* route: foreign-Origin POST 403 even with a valid token, same-Host no-Origin tokenless form POST 401, Origin `null` 403 (`web_integration_spec.rb:127-143`) — the three shapes a browser page can actually produce against localhost (CP13) | closed |
| T-13-19 | Information disclosure (gem ships without dashboard assets) | spm_cache.gemspec files glob | medium | mitigate | all four assets pinned inside `Gem::Specification.files` + glob-ships-the-dir pin (`web_packaging_spec.rb:35-47`); real `gem build` smoke asserts the built .gem carries them (`web_packaging_spec.rb:69-95`); glob at `spm_cache.gemspec:13-15` | closed |
| T-13-20 | DoS (unbounded spec runtime / extra server boots) | integration + packaging specs | low | mitigate | single before-all port-0 boot, `order: :defined` (`web_integration_spec.rb:26`); whole-file < 15 s monotonic runtime bound (`web_integration_spec.rb:251-255`); packaging spec boots nothing | closed |
| T-13-21 | Tampering (regression: refs that only resolve via test-side rewriting re-ship) | spec/web_integration_spec.rb page-load example | high | mitigate | refs pinned prefixed AND resolved browser-honestly — `URI.join` against the document origin → `request_uri`, no `/assets/` construction in the request path (`web_integration_spec.rb:176-193`); reverting index.html to bare refs fails the suite by name | closed |
| T-13-22 | Tampering (fix shipped by weakening the relative-only offline pins) | spec/web_frontend_spec.rb:71-75 | medium | mitigate | relative-only negative pins verbatim — no leading-slash, no protocol-relative, no scheme-absolute references (`web_frontend_spec.rb:69-79`); the relative `assets/` prefix satisfies them unedited (RED→GREEN through 13-05 without touching the pins) | closed |
| T-13-23 | Information disclosure / traversal (new refs point outside the served set) | index.html refs | low | accept | the three refs (`index.html:8`, `index.html:55-56`) are the same validated basenames crossing the UNCHANGED `/assets/*` dispatch (`router.rb:76-80`) + Web::Assets root containment (`assets.rb:37-42`) — an attribute-value prefix introduces no traversal or disclosure path | closed (accepted) |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on (high) count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-13-08 | T-13-08 | Port-probe exhaustion and request-flood DoS against a localhost single-user dev tool: the probe is bounded (25 attempts, clear error) and WEBrick per-request threads are acceptable at dev-tool request rates; no untrusted-boundary amplification beyond what any local process can already do | Plan-time disposition, confirmed at audit | 2026-09-01 |
| AR-13-23 | T-13-23 | The `assets/` ref prefix changes only attribute values in index.html — the request still crosses the same Host-gated `/assets/*` dispatch into unchanged basename validation and root containment; no new file becomes reachable | Plan-time disposition, confirmed at audit (68ff6f8 diff re-read: exactly 3 relative-ref lines) | 2026-09-01 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-09-01 | 23 | 23 | 0 | gsd secure-phase (SecAudit13 audit agent, ASVS L1, code-cited at HEAD ea23632) |

Evidence basis: every mitigate disposition verified by direct code read with file:line cites (table above), not by documentation. Live audit greps over `lib/spm_cache/web/assets/app.js`: zero matches for `innerHTML|outerHTML|insertAdjacentHTML|document.write|eval(|new Function|.html(` and for `Date.now` — T-13-13/T-13-16 posture confirmed at source level. `cytoscape.min.js` first line read and byte-count stat'd (435,643 bytes, version comment without scheme URL) — T-13-14. `.gitignore` carries `.spm-cache/`; `core/run_log.rb:103` excludes the web verb from run logs (`main_log_skipped: %w[web watch]`) — T-13-03. Cross-checks: `spec/web_integration_spec.rb` (25-cell matrix :71-123, drive-by trio :127-143, browser-honest page-load :158-193, header sweep :226-240, <15 s bound :251-255), `spec/web_packaging_spec.rb` (files pins :35-47, webrick `>= 1.8, < 2` requirement-object pin :50-66, gem-build smoke :69-95, cytoscape structural pins :111-121), `spec/web_frontend_spec.rb` (bootstrap ordering :105-112, header/DOM pins :114-121, Date.now ban :209-212, XSS hygiene :219-223, relative-only pins :69-79), `spec/web_middleware_spec.rb` (fixed-time compare :79-82). webrick window `>= 1.8, < 2` declared at `spm_cache.gemspec:31` (scope cross-check). Code review (13-REVIEW.md → 13-REVIEW-FIX.md): 8/8 findings fixed; WR-01's error-envelope rescue (`router.rb:126-133`, `router.rb:155-158`) closes the terminal-backtrace vector the review flagged against T-13-03 posture. Post-fix full suite 787 examples, 0 failures.

Post-verification delta audit (the gap-closure since verified HEAD 049503b): commits 5cc40cf → ea23632; the ONLY production-source change is 68ff6f8 (index.html, 3 lines — the three asset refs gain the relative `assets/` prefix; 8fdd2df and 5cc40cf are spec-side). Diff re-read at audit: refs stay relative, same-origin, scheme-free — they resolve through the unchanged Host-gated `/assets/*` dispatch into unchanged basename validation; no new surface, no weakening of any pin (T-13-21/22/23 all re-verified above). No other threat's mitigation site was touched. Orchestrator's independent headless-Chromium run against a live boot corroborates the runtime posture: token bootstrap cleans the URL to '/', 64-char token in sessionStorage never in the DOM, wrong-token yields the full-page restart copy, rows retained on server-kill.

Unregistered flags from per-plan SUMMARY `## Threat Flags`: none — 13-01/13-02 report "no security-relevant surface beyond the plan's threat_model"; 13-03/13-04/13-05 report dispositions implemented with no surface beyond the model.

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-09-01
