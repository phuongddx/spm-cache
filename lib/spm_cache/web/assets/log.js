// spm-cache run log (Phase 14-04) — the dashboard's sibling ES
// module, no framework, no build step, fully offline (14-CONTEXT).
// Consumes the 14-01 SSE wire contract: named events
// hello/entry/switch/notice over GET /api/events. Stored-XSS defense
// (T-14-16): log text, package names, run ids, and argv are untrusted
// subprocess output — every dynamic string renders through
// el()/textContent; this file never assigns markup strings to the
// DOM. No client clock (T-14-17): relative times derive from the
// server 'now' stamp and event ts only. No timers: the state poll in
// app.js stays the dashboard's only timer (T-14-20) — the stream is
// push-only and the two modules share nothing but sessionStorage.
(() => {
  'use strict';

  const TOKEN_KEY = 'spm-cache-web-token'; // the key app.js wrote at bootstrap — the shared seam, never imports
  const RING_LIMIT = 500; // D-02: the DOM holds the newest 500 line elements

  // -- DOM helpers (textContent only — never markup strings) --------
  const byId = (id) => document.getElementById(id);
  const el = (tag, opts = {}) => {
    const node = document.createElement(tag);
    if (opts.class) node.className = opts.class;
    if (opts.text !== undefined) node.textContent = opts.text;
    if (opts.title) node.title = opts.title;
    if (opts.type) node.type = opts.type; // buttons always declare type=button — never a submit
    if (opts.value !== undefined) node.value = opts.value; // dropdown options carry the run id
    if (opts.disabled) node.disabled = true; // the placeholder entries ('No runs yet', 'Loading…')
    return node;
  };

  // -- pinned copy (14-UI-SPEC Copywriting Contract — byte-exact) ---
  const COPY = {
    connecting: '● connecting…',
    connected: '● connected',
    reconnecting: '↻ reconnecting…',
    tokenInvalid: "This page's access token is no longer valid. Restart spm-cache web and open the URL it prints.",
    loading: 'Loading…',
    noRunsTitle: 'No runs yet',
    errPrefix: '✗ ',
    redactedSuffix: ' · credentials redacted',
    jumpToError: 'Jump to first error',
    interruptedBanner: 'Run interrupted — exit unknown.',
    failedBanner: (status) => `Run failed — exit status ${status}`,
    paused: (n) => `paused — ${n} new lines · jump to live`,
    filtered: (name) => `filtered: ${name}`,
    switchNotice: 'switched to new run — previous: ',
    viewingSuffix: ' · viewing',
    runsError: (message) => `Couldn't load the run list: ${message}. Reload the page to retry.`,
    elision: (n) => `… ${n} earlier lines — reload to replay from start`,
    divider: (name) => `── ${name} ──`,
    notice: (message) => `! ${message}`,
  };

  // -- card vocabularies (14-UI-SPEC status-colors table) -----------
  // Glyph+word pairs — no color-only encoding (Prohibition 3). The
  // verdict triple ✓/!/✗ is reused from the Phase 13 vocabulary; ●
  // and ↻ are this phase's liveness glyphs.
  const RUN_STATUS = {
    running: { glyph: '●', word: 'running', cls: 'log-live' },
    success: { glyph: '✓', word: 'success', cls: 'log-ok' },
    failed: { glyph: '✗', word: 'failed', cls: 'log-fail' },
    interrupted: { glyph: '!', word: 'interrupted — exit unknown', cls: 'log-warn' },
  };

  // D-11: trigger values render VERBATIM — this map picks a class
  // only (watch = the machine/automation indigo precedent). There is
  // no allowlist and no special case, so unknown values and Phase
  // 15's 'UI' badge render unchanged in the neutral class.
  const TRIGGER_CLASS = { watch: 'plugin' };

  // -- relative time over SERVER stamps only (T-14-17) --------------
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  // D-12 entry template: '{glyph} {command} · {relative}' — the glyph
  // per the server's derived status (the same vocabulary the card
  // renders; CP14's phrase carries the full 'interrupted — exit
  // unknown' string, so the map keys it exactly).
  const RUNS_GLYPH = {
    running: '●',
    success: '✓',
    failed: '✗',
    'interrupted — exit unknown': '!',
  };

  const pad2 = (n) => String(n).padStart(2, '0');
  const fmtStamp = (iso) => {
    const d = new Date(iso);
    if (!Number.isFinite(d.getTime())) return '';
    return `${MONTHS[d.getMonth()]} ${d.getDate()}, ${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
  };

  // Vocabulary (14-UI-SPEC): 'just now' < 60s · '{N} min ago' ·
  // '{N} hr ago' · '{MMM d, HH:MM}' at ≥ 24h (the "ago" phrasing
  // drops). serverNowTs is the hello 'now' stamp, re-derived on each
  // hello — never the client clock.
  const relative = (iso) => {
    if (!iso) return '';
    const then = new Date(iso).getTime();
    if (!Number.isFinite(then)) return '';
    if (serverNowTs === null) return fmtStamp(iso); // no server stamp yet: absolute form, never a guess
    const seconds = Math.max(0, Math.floor((serverNowTs - then) / 1000));
    if (seconds < 60) return 'just now';
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) return `${minutes} min ago`;
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return `${hours} hr ago`;
    return fmtStamp(iso);
  };

  // -- module state ---------------------------------------------------
  let source = null;
  let dead = false; // set once the token-invalid page replaces the panels — every handler bails
  let activeFilter = null; // D-09/D-10: 14-05's filter state rides here; jumps clear it first
  let serverNowTs = null;
  let currentRun = null;
  let currentHeader = {};
  let cardPending = false;
  let ringCount = 0;
  let evicted = 0;
  let elisionEl = null;
  let follow = false;   // D-01: engages at replay completion, never mid-replay
  let replaying = false;
  let pending = 0;      // lines queued while paused (D-01) — live-incrementing, uncapped
  let lastScrollTop = 0;
  let firstErrEl = null;  // D-03 jump anchor: the first error-styled line
  let errEvicted = false; // D-02: the anchor fell out of the ring
  let runEndInfo = null;
  // -- 14-05 anchor + filter state --------------------------------------
  // SEG maps each line element to its segment identity as the entries
  // stream (live and replay share the one entry path); anchors is the
  // D-07 position registry the chip jumps ride.
  const SEG = new WeakMap(); // per-line segment identity (pkg/phase)
  const anchors = [];        // D-07: ordered anchor records — the position registry
  let segPackage = null;     // the package segment streaming now (package_start..package_end)
  let segPhase = null;       // the phase segment (marker .. next marker/package_start)
  let pinned = false;        // true while the stream URL carries 14-03's ?run= param (loadRun)
  let lastRuns = null;       // the last good /api/runs list — a RENDER cache only; every open re-fetches
  let runsFetching = false;  // in-flight dedupe — never a response cache (CP10 client-side)

  const storedToken = () => sessionStorage.getItem(TOKEN_KEY);

  // -- DOM refs --------------------------------------------------------
  const body = byId('log-body');
  const card = byId('log-card');
  const statusEl = byId('log-status');
  const triggerEl = byId('log-trigger');
  const commandEl = byId('log-command');
  const configEl = byId('log-config');
  const startedEl = byId('log-started');
  const argvEl = byId('log-argv');
  const runIdEl = byId('log-runid');
  const bannerEl = byId('log-banner');
  const viewport = byId('log-viewport');
  const pill = byId('conn-pill');
  const railPhases = byId('rail-phases');
  const railPackages = byId('rail-packages');
  const switchBar = byId('log-switch');
  const switchBtn = byId('log-switch-btn');
  const runsSelect = byId('log-runs');
  const bannerTextEl = byId('log-banner-text');
  const bannerJumpBtn = byId('log-banner-jump');
  const pauseBtn = byId('log-follow-btn');
  const filterBtn = byId('log-filter-pill');
  const topbarStateEl = byId('topbar-state');
  const runstatCmdEl = byId('runstat-cmd');
  const logCountEl = byId('log-count');

  // -- token-invalid terminal page (the locked 13 sentence) -----------
  // A CLOSED EventSource is permanent (research A6): any non-200
  // kills reconnection, so auth-dead tabs must see a terminal state,
  // never a promise of reconnection.
  const renderTokenInvalid = () => {
    if (dead) return;
    dead = true;
    const main = document.querySelector('.app');
    if (main) main.replaceChildren(el('p', { class: 'error-page', text: COPY.tokenInvalid }));
  };

  // Teardown safety: once the panels are replaced (this module's
  // CLOSED path or app.js's 401 path), no handler touches the dead
  // DOM — the app.js "panels replaced → bail out" guard, re-checked
  // on every event.
  const alive = () => {
    if (dead) return false;
    if (!byId('log-viewport')) { dead = true; return false; }
    return true;
  };

  // -- connection pill (the panel's liveness marker) -------------------
  const setPill = (state) => {
    pill.textContent = COPY[state];
    pill.className = state === 'connected'
      ? 'conn-pill conn-pill-connected log-live'
      : `conn-pill${state === 'reconnecting' ? ' conn-pill-reconnecting' : ''}`;
  };

  // -- follow/pause (D-01) ----------------------------------------------
  // Instant only (Prohibition 4): follow and jumps set the scroll
  // position directly — never an eased or animated scroll.
  const atBottom = () => viewport.scrollHeight - viewport.scrollTop - viewport.clientHeight < 2;
  const stick = () => { viewport.scrollTop = viewport.scrollHeight; };

  // The pause pill is ONE button carrying its whole label — the
  // accessible name IS the visible label. It appears only when new
  // lines are genuinely queued while paused: never mid-replay (a
  // live-tail affordance only) and never while following.
  // app-shell port: `#log-follow-btn` and `#log-filter-pill` are now
  // static markup-with-real-wiring (context decision 3) — patched in
  // place, never created/appended; their click listeners attach ONCE
  // at boot().
  const renderPill = () => {
    if (!replaying && !follow && pending >= 1) {
      pauseBtn.hidden = false;
      pauseBtn.textContent = COPY.paused(pending); // the {N} live-increments on the surviving node
    } else {
      pauseBtn.hidden = true;
    }
    if (activeFilter) {
      filterBtn.hidden = false;
      filterBtn.textContent = COPY.filtered(activeFilter.name);
      filterBtn.title = COPY.filtered(activeFilter.name);
    } else {
      filterBtn.hidden = true;
    }
  };

  const resumeFollow = () => {
    if (!alive()) return;
    follow = true;
    replaying = false;
    pending = 0;
    renderPill();
    stick();
  };

  const bindScroll = () => {
    viewport.addEventListener('scroll', () => {
      if (!alive()) return;
      const goingUp = viewport.scrollTop < lastScrollTop;
      lastScrollTop = viewport.scrollTop;
      replaying = false; // any interaction leaves passive replay-watching
      if (goingUp) follow = false; // D-01: ANY upward scroll disengages
    });
  };

  // -- cold load + stream state (D-13) ---------------------------------
  const removeLoading = () => { body.querySelector('.loading')?.remove(); };

  const resetForRun = (name, followOn) => {
    currentRun = name;
    cardPending = true; // the replayed run_start header rebuilds the card (the switch path carries no fresh hello)
    viewport.replaceChildren();
    ringCount = 0;
    evicted = 0;
    elisionEl = null;
    runEndInfo = null;
    firstErrEl = null;
    errEvicted = false;
    pending = 0;
    lastScrollTop = 0;
    follow = !!followOn; // D-04: an auto-switch drops the viewer at the new run's tail
    replaying = true;
    anchors.length = 0;  // D-07: chips belong to the displayed run — its replay re-derives them
    segPackage = null;   // segment bookkeeping restarts with the replay (D-09)
    segPhase = null;
    activeFilter = null; // D-04: a switch clears the filter — the fresh run re-derives everything
    renderChips();
    syncRunsViewing(); // D-12: ' · viewing' tracks the displayed run
    hideBanner();
    renderPill();
    updateLogCount();
  };

  const renderEmptyState = () => {
    // D-13 empty branch: the copy owns the panel — card and banner
    // stay hidden and only the connection pill lives.
    currentRun = null;
    cardPending = false;
    card.hidden = true;
    viewport.replaceChildren();
    ringCount = 0;
    evicted = 0;
    elisionEl = null;
    runEndInfo = null;
    firstErrEl = null;
    errEvicted = false;
    pending = 0;
    follow = false;
    replaying = false;
    anchors.length = 0;  // no run displayed — the rail keeps only its labels
    segPackage = null;
    segPhase = null;
    activeFilter = null;
    renderChips();
    syncRunsViewing();
    hideBanner();
    renderPill();
    updateLogCount();
    const para = el('p', { class: 'empty-body' });
    para.append('Run ', el('span', { class: 'cmd', text: 'spm-cache build' }), ' to produce the first run log.');
    viewport.append(el('h3', { class: 'empty-title', text: COPY.noRunsTitle }), para);
  };

  // -- identity card (D-06) ---------------------------------------------
  // hello statuses: the server derivation is authoritative; a
  // 'completed' run's exact exit state (✓/✗) refines when its run_end
  // line replays — a missing run_end never derives completion.
  const statusKey = (status) => {
    // The server's CP14 vocabulary (hello + /api/runs) carries the FULL
    // phrase; both spellings map to interrupted — a bare-word compare let
    // the phrase fall through to running (D-14 probe catch).
    if (status === 'interrupted' || status === 'interrupted — exit unknown') return 'interrupted';
    if (status === 'failed') return 'failed';
    if (status === 'success' || status === 'completed') return 'success';
    return 'running';
  };

  // Topbar mirror (app-shell port): the SAME derived status word/glyph
  // additionally lands in `#topbar-state`, visible on every surface —
  // no new data source, just a second DOM target for the fact already
  // computed above.
  const TOPBAR_STATE_SUFFIX = { running: 'run', success: 'ok', failed: 'fail', interrupted: 'warn' };

  const setCardStatus = (key) => {
    const status = RUN_STATUS[key] || RUN_STATUS.running;
    statusEl.className = `log-status ${status.cls}`;
    statusEl.textContent = `${status.glyph} ${status.word}`;
    if (topbarStateEl) {
      topbarStateEl.className = `state-pill state-${TOPBAR_STATE_SUFFIX[key] || 'idle'}`;
      topbarStateEl.textContent = `${status.glyph} ${status.word}`;
    }
  };

  // A2: the header attributes the build config when it can; absent
  // means unattributable — the honest dash, never a guess.
  const attributableConfig = () => {
    const config = currentHeader.config;
    return typeof config === 'string' && config ? config : '—';
  };

  const argvRow = () => {
    const parts = Array.isArray(currentHeader.argv) ? currentHeader.argv : [];
    let text = `spm-cache ${parts.join(' ')}`;
    if (currentHeader.redacted) text += COPY.redactedSuffix;
    return text;
  };

  const renderTimes = () => {
    const startedIso = currentHeader.started_at || currentHeader.ts;
    let text = `Started ${fmtStamp(startedIso)}`;
    const endIso = runEndInfo && (runEndInfo.ended_at || runEndInfo.ts);
    if (endIso) text += ` · completed ${relative(endIso)}`; // {relative} already carries the ago phrasing (vocabulary row)
    startedEl.textContent = text;
  };

  const buildCard = (header, key) => {
    currentHeader = header && typeof header === 'object' ? header : {};
    cardPending = false;
    card.hidden = false; // no card until the hello payload arrives
    setCardStatus(key);
    triggerEl.className = `badge badge-${TRIGGER_CLASS[currentHeader.trigger] || 'neutral'}`;
    triggerEl.textContent = currentHeader.trigger || '—';
    commandEl.textContent = currentHeader.command || '';
    if (runstatCmdEl) runstatCmdEl.textContent = currentHeader.command || ''; // topbar mirror — same source, no new data
    configEl.textContent = `Config ${attributableConfig()}`;
    renderTimes();
    const argvText = argvRow();
    argvEl.textContent = argvText;
    argvEl.title = argvText; // full value on hover — the row itself CSS-ellipsizes
    runIdEl.textContent = currentRun || '';
    runIdEl.title = currentRun || '';
  };

  // -- the render ring (D-02) --------------------------------------------
  // The elision notice is plain text, never clickable — reload is the
  // replay affordance, and the full run always stays on disk.
  const evictOldest = () => {
    const oldest = viewport.querySelector('.log-line');
    if (!oldest) return;
    if (oldest === firstErrEl) { firstErrEl = null; errEvicted = true; }
    if (!elisionEl) {
      elisionEl = el('div', { class: 'log-elision' });
      viewport.insertBefore(elisionEl, viewport.firstChild);
    }
    oldest.remove();
    ringCount -= 1;
    evicted += 1;
    elisionEl.textContent = COPY.elision(evicted);
  };

  // `#log-count` mirrors ringCount + evicted — the DOM's retained lines
  // plus everything the ring has already dropped, so the number always
  // reads as "total lines seen this run", not just "lines on screen".
  const updateLogCount = () => {
    if (logCountEl) logCountEl.textContent = `${ringCount + evicted} lines`;
  };

  const appendLine = (node) => {
    node.classList.toggle('log-dim', !matches(node)); // live classification under an active filter (D-09)
    viewport.append(node);
    ringCount += 1;
    if (ringCount > RING_LIMIT) evictOldest();
    updateLogCount();
    if (replaying && atBottom()) replaying = false; // D-13: the whole file fits — nothing above to pause for
    if (follow) {
      stick();
    } else if (!replaying && atBottom()) {
      follow = true; // bottom-stick: the viewer rides the tail and a new line arrives
      stick();
    } else if (!replaying) {
      pending += 1; // queued while paused — {N} live-incrementing, uncapped
      renderPill();
    }
  };

  // -- failure + interrupt banners (D-03/CP14) ---------------------------
  // The banner belongs to the displayed run: sticky, no close control,
  // replaced only when another run's replay re-derives the slot.
  // app-shell port: `#log-banner-text` and the jump button are static
  // markup-with-real-wiring (context decision 3) — patched in place;
  // the jump button's click listener attaches ONCE at boot().
  const showBanner = (kind, status) => {
    const failed = kind === 'failed';
    bannerEl.className = `log-banner ${failed ? 'log-banner-fail' : 'log-banner-warn'}`;
    const glyphEl = bannerEl.querySelector('.log-banner-glyph');
    if (glyphEl) {
      glyphEl.className = `log-banner-glyph ${failed ? 'log-fail' : 'log-warn'}`;
      glyphEl.textContent = failed ? '✗' : '!';
    }
    bannerTextEl.textContent = failed ? COPY.failedBanner(status) : COPY.interruptedBanner;
    bannerEl.hidden = false;
  };

  const hideBanner = () => {
    bannerEl.hidden = true;
  };

  // D-10 seam: failure visibility beats filter intent — jumping exits
  // the filter before moving the view. One revert path for every exit:
  // the active chip, the filter pill, and the jump-to-error all land
  // here (pill removed, dim removed, chips revert — positions stable).
  const clearFilter = () => {
    if (!activeFilter) return;
    activeFilter = null;
    viewport.querySelectorAll('.log-line.log-dim').forEach((line) => line.classList.remove('log-dim'));
    renderChips();
    renderPill();
  };

  // Never a dead control, never a silent no-op: the first error-styled
  // line → the run's final line → under ring eviction the oldest
  // retained line (the head notice names the reload affordance) → the
  // top of a zero-line run.
  const jumpTarget = () => {
    if (firstErrEl && firstErrEl.isConnected) return firstErrEl; // the first error-styled line, still in the ring
    const errs = viewport.querySelectorAll('.log-line.log-err');
    const lines = viewport.querySelectorAll('.log-line');
    if (errEvicted && lines.length > 0) return lines[0]; // the anchor was evicted — the oldest retained line (D-02)
    if (errs.length > 0) return errs[0]; // defensive: an error line is retained though the anchor was lost
    if (lines.length > 0) return lines[lines.length - 1]; // no err line — the run's final line
    return null; // zero-line run — the top, never a dead control
  };

  const jumpToFirstError = () => {
    if (!alive()) return;
    clearFilter();
    follow = false; // jumps disengage follow identically (D-01)
    replaying = false;
    const target = jumpTarget();
    viewport.scrollTop = target ? target.offsetTop : 0;
  };

  // -- anchor rail + filter engine (D-07/D-08/D-09, 14-05) --------------
  // D-09 segment rules: a package filter matches its package_start..
  // package_end segment inclusive; a phase filter matches from the
  // marker to the line before the next phase marker or package_start.
  // Untagged lines — anything before the first anchor, server notices —
  // match nothing and dim under any filter.
  const matches = (line) => {
    if (!activeFilter) return true;
    const seg = SEG.get(line);
    if (!seg) return false;
    return activeFilter.kind === 'package' ? seg.pkg === activeFilter.name : seg.phase === activeFilter.name;
  };

  // A5: filtering DIMS via the muted color — never hides; line
  // positions stay stable, which is what makes D-10's real-position
  // jump possible. Pure CSS-class toggling over the ring: no DOM
  // restructuring, layout never shifts.
  const applyFilter = () => {
    viewport.querySelectorAll('.log-line').forEach((line) => {
      line.classList.toggle('log-dim', !matches(line));
    });
  };

  // D-07: chips render only as their anchor events arrive — zero
  // placeholders, and nothing for no-line or unknown events. A10:
  // names dedupe by name, first position wins (defensive only in the
  // frozen Phase-12 vocabulary).
  const addAnchor = (kind, name, lineEl) => {
    if (anchors.some((a) => a.kind === kind && a.name === name)) return;
    anchors.push({ kind, name, lineEl });
    renderChips();
  };

  // The rail's two groups (labels always rendered); chips are native
  // buttons — DOM-order tabbing, Enter/Space activation. The active
  // chip carries aria-pressed and the accent badge style (A3: accent
  // text on a 10%-alpha fill).
  // W3 (14-UI-REVIEW → 15 polish): chips RECONCILE against the anchor
  // list — an unchanged chip's node survives every re-render (creation
  // and append happen only for genuinely new anchors; aria-pressed and
  // the active class are patched in place), so a keyboard user's focus
  // survives anchor arrivals during a live run. Removal fires only for
  // chips whose anchor left the set (a run switch clears the rail).
  const renderChips = () => {
    if (!railPhases || !railPackages) return;
    [railPhases, railPackages].forEach((group) => {
      group.querySelectorAll('.log-chip').forEach((chip) => {
        if (!anchors.some((a) => a.chipEl === chip)) chip.remove();
      });
    });
    anchors.forEach((anchor) => {
      const isActive = activeFilter
        && activeFilter.kind === anchor.kind && activeFilter.name === anchor.name;
      let chip = anchor.chipEl;
      if (!chip || !chip.isConnected) {
        chip = el('button', { type: 'button', class: 'log-chip', text: anchor.name, title: anchor.name });
        chip.addEventListener('click', () => onChip(anchor));
        anchor.chipEl = chip;
        (anchor.kind === 'phase' ? railPhases : railPackages).append(chip);
      }
      chip.setAttribute('aria-pressed', isActive ? 'true' : 'false');
      chip.classList.toggle('log-chip-active', isActive);
    });
  };

  // D-09: a chip click jumps to the anchor's divider AND sets the
  // filter; clicking the ACTIVE chip clears the filter instead — the
  // view stays put on either exit.
  const onChip = (anchor) => {
    if (!alive()) return;
    const isActive = activeFilter
      && activeFilter.kind === anchor.kind && activeFilter.name === anchor.name;
    if (isActive) {
      clearFilter(); // the active chip toggles its filter off — the view stays put
      return;
    }
    activeFilter = { kind: anchor.kind, name: anchor.name };
    applyFilter();
    renderChips();
    renderPill();
    jumpToAnchor(anchor);
  };

  // D-09 jumps ride the position registry (anchor identity → line
  // element). Under ring eviction the target degrades to the oldest
  // retained line — never a no-op; the head notice already names the
  // reload affordance (the same degradation the error jump applies).
  const anchorTarget = (anchor) => {
    if (anchor.lineEl && anchor.lineEl.isConnected) return anchor.lineEl;
    const lines = viewport.querySelectorAll('.log-line');
    return lines.length > 0 ? lines[0] : null;
  };

  const jumpToAnchor = (anchor) => {
    follow = false; // jumps disengage follow identically (D-01)
    replaying = false;
    const target = anchorTarget(anchor);
    viewport.scrollTop = target ? target.offsetTop : 0;
  };


  // -- spm-run-progress (A10 — the one sanctioned coupling) ----------
  // Displayed-run milestones for the controls row (15-05): ONE DOM
  // CustomEvent dispatched from exactly the body-line and run-end code
  // points — no traversal, no timer, no shared state; the modules
  // still share nothing beyond sessionStorage. The stream is
  // per-connection pinned to the displayed run, so emission is
  // displayed-run-scoped by construction. WAIT_LINE is byte-identical
  // to the Installer's frozen announce (14-02 D-05); the wait line
  // itself still renders verbatim as a plain out line — this is the
  // milestone channel only.
  //
  // WR-01: "displayed-run-scoped" alone is not "the-run-the-click-
  // spawned-scoped" — a pinned (user-selected) run's own body-line/
  // run-end events would otherwise fire milestones for whatever the
  // viewer happens to show, including an unrelated finished run
  // replaying mid-flight while a real build is in progress. `pinned`
  // is the correct, non-flickering gate (unlike `replaying`, which can
  // flip false mid-replay once the viewport reaches the bottom):
  // onSwitchEvent unconditionally clears `pinned` the instant ANY
  // run's switch broadcast lands, so by the time `currentRun` genuinely
  // becomes the click-spawned run, `pinned` is already false again —
  // suppressing emission while pinned never withholds a milestone for
  // the run that was actually started.
  const WAIT_LINE = 'Waiting for build lock…';
  const emitProgress = (phase) => {
    if (pinned) return;
    document.dispatchEvent(new CustomEvent('spm-run-progress', { detail: { phase } }));
  };

  // -- entry rendering, keyed ONLY on the parsed event field (T-12-01) ---
  const appendBody = (data) => {
    const raw = typeof data.text === 'string' ? data.text : '';
    const text = raw.replace(/\n$/, ''); // one trailing newline is framing, not content
    const isErr = data.stream === 'err';
    const line = el('div', {
      class: isErr ? 'log-line log-err' : 'log-line',
      text: isErr ? COPY.errPrefix + text : text, // ANSI codes are data — literal characters, no interpretation
    });
    if (isErr && !firstErrEl) firstErrEl = line;
    SEG.set(line, { pkg: segPackage, phase: segPhase }); // segment identity for D-09 matching
    appendLine(line);
    if (text === WAIT_LINE) {
      emitProgress('waiting'); // the run's own bytes say it is blocked on the flock (A2)
    } else {
      emitProgress('active'); // any following line proves the wait ended (A2)
    }
  };

  const onRunEnd = (data) => {
    emitProgress('ended'); // the same facts that flip the card end the row's in-flight state (A7)
    runEndInfo = data; // ended_at drives the completed-ago suffix
    renderTimes();
    replaying = false; // a finished file's replay IS complete at its last line
    const status = typeof data.status === 'number' ? data.status : 0;
    if (status !== 0) {
      setCardStatus('failed');
      showBanner('failed', status);
    } else {
      setCardStatus('success');
      hideBanner();
    }
  };

  const renderEntry = (data) => {
    if (data.event === 'run_start') {
      if (cardPending) buildCard(data, 'running');
      return; // no line — the card is its surface
    }
    if (data.event === 'run_end') {
      onRunEnd(data);
      return; // no line — the card and banner are its surface
    }
    if (data.event === 'package_start' || data.event === 'phase') {
      const name = typeof data.name === 'string' ? data.name : '';
      const divider = el('div', {
        class: 'log-line log-divider',
        text: COPY.divider(name),
      });
      if (data.event === 'package_start') {
        SEG.set(divider, { pkg: name, phase: null }); // the divider anchors its own segment
        addAnchor('package', name, divider);
        segPackage = name;
        segPhase = null; // a package_start ends the phase segment (D-09)
      } else {
        SEG.set(divider, { pkg: null, phase: name });
        addAnchor('phase', name, divider);
        segPhase = name;
      }
      appendLine(divider); // dividers are the jump targets (D-07)
      return;
    }
    if (data.event === 'package_end' || data.event === 'sh') {
      if (data.event === 'package_end') segPackage = null; // the segment closes — later lines dim under its filter
      return; // no line
    }
    if (data.event === 'sh') return; // no line
    if (data.event !== undefined) return; // unknown keys ignored — forward-compatible (T-12-01)
    appendBody(data);
  };

  // -- named events (the 14-01 wire contract) -----------------------------
  const parseData = (e) => {
    try {
      const parsed = JSON.parse(e.data);
      return parsed && typeof parsed === 'object' ? parsed : null;
    } catch {
      return null;
    }
  };

  const onHelloEvent = (e) => {
    if (!alive()) return;
    const payload = parseData(e);
    if (!payload) return;
    const nowTs = payload.now ? new Date(payload.now).getTime() : null;
    if (Number.isFinite(nowTs)) serverNowTs = nowTs; // the only clock — re-derived on every hello
    removeLoading();
    if (!payload.run || payload.status === 'idle') { renderEmptyState(); return; }
    if (payload.run !== currentRun) {
      resetForRun(payload.run, false);
      buildCard(payload.header, statusKey(payload.status));
    } else if (cardPending) {
      buildCard(payload.header, statusKey(payload.status)); // a loadRun/switch reconnect: hello's header rebuilds the card
    } else {
      setCardStatus(statusKey(payload.status)); // reconnect: identity re-derived from disk per CP10
    }
    if (statusKey(payload.status) === 'interrupted') showBanner('interrupted');
  };

  const onEntryEvent = (e) => {
    if (!alive()) return;
    const data = parseData(e);
    if (data) renderEntry(data);
  };

  const onNoticeEvent = (e) => {
    if (!alive()) return;
    const data = parseData(e);
    if (data && typeof data.message === 'string') {
      appendLine(el('div', { class: 'log-line log-notice', text: COPY.notice(data.message) }));
    }
  };

  // D-04: a new run's arrival switches the stream UNCONDITIONALLY —
  // payload validity is the only guard, never view state (even
  // mid-read of an older run). 14-03 delivers switch broadcasts to
  // pinned connections too: the handler answers by dropping the pin,
  // closing the stream, and reconnecting via the plain URL
  // (current-or-newest IS the new run). On an unpinned connection the
  // tailer already replays the new file from byte 0 after the event —
  // the in-place reset lands in the identical rendered state.
  const onSwitchEvent = (e) => {
    if (!alive()) return;
    const data = parseData(e);
    if (!data || typeof data.run !== 'string') return;
    // The notice names the previously-DISPLAYED run — the client's own
    // view state, NOT the event's previous field: the two diverge on
    // ?run= pins (pinned on A while the tailer serves B, a new run C
    // broadcasts its tailer-side previous — the user was viewing A).
    const previousRun = currentRun;
    resetForRun(data.run, true);
    renderSwitchNotice(previousRun);
    if (pinned) {
      pinned = false;
      if (source) source.close();
      connect(storedToken());
    }
  };

  // D-04/A7: ONE notice slot between card and stream — a newer switch
  // replaces the text; the bar is persistent and never auto-cleared
  // (only a newer switch rewrites it). No previously-displayed run →
  // no notice at all: the first run of a session and a switch into
  // the empty state simply populate the card.
  // app-shell port: the static label + `#log-switch-btn` are reused in
  // place (context decision 3); `switchTargetRun` remembers which run
  // the persistent button's click should load, since the closure the
  // old per-call button captured no longer exists.
  let switchTargetRun = null;
  const renderSwitchNotice = (previousRun) => {
    if (!switchBar || !previousRun) return;
    switchBar.hidden = false;
    switchTargetRun = previousRun;
    switchBtn.textContent = previousRun;
    switchBtn.title = previousRun; // run ids inside notices ellipsize with tooltips (long-text row)
  };

  // D-04/D-12: ONE in-place load path — the notice's run-id control
  // and every dropdown selection funnel here (no page reload, no
  // second replay mechanism): close the stream, reconnect pinned via
  // 14-03's ?run= param, replay from byte 0. A finished selection
  // replays with follow off; a live one re-engages at the tail (D-12).
  const loadRun = (name) => {
    if (!alive() || typeof name !== 'string' || !name || name === currentRun) return;
    pinned = true;
    if (source) source.close();
    resetForRun(name, false);
    connect(storedToken(), name);
  };

  // -- recent-runs dropdown (D-12) ---------------------------------------
  // The dropdown's own token-gated request layer — the app.js pattern
  // duplicated (the modules never import each other; app.js's fetch is
  // its failure domain). Envelope {status,data} checked; 401/403 takes
  // the locked token-invalid page (the stream is dying too).
  const fetchRunsList = async () => {
    let res;
    try {
      res = await window.fetch('/api/runs', { headers: { 'X-SPM-Token': storedToken() } });
    } catch (err) {
      throw new Error(`network error (${err.message})`);
    }
    if (res.status === 401 || res.status === 403) {
      renderTokenInvalid();
      throw new Error('unauthorized');
    }
    const envelope = await res.json().catch(() => ({ status: 'error', data: { message: `HTTP ${res.status}` } }));
    if (!res.ok || envelope.status === 'error') {
      throw new Error((envelope.data && envelope.data.message) || `HTTP ${res.status}`);
    }
    return envelope.data || {};
  };

  const runsEntryText = (entry) => {
    const glyph = RUNS_GLYPH[entry.status] || '●';
    const viewing = entry.run === currentRun ? COPY.viewingSuffix : '';
    return `${glyph} ${entry.command} · ${relative(entry.started_at)}${viewing}`;
  };

  // The server lists newest-first at its 10-entry bound; the client
  // renders in that order. Empty dir (or nothing landed) renders the
  // single disabled 'No runs yet' entry.
  const renderRunsOptions = (runs) => {
    if (!runsSelect) return;
    runsSelect.replaceChildren();
    if (!runs || runs.length === 0) {
      runsSelect.append(el('option', { text: COPY.noRunsTitle, disabled: true }));
      return;
    }
    runs.forEach((entry) => {
      runsSelect.append(el('option', {
        value: typeof entry.run === 'string' ? entry.run : '',
        text: runsEntryText(entry),
      }));
    });
    if (currentRun) runsSelect.value = currentRun;
  };

  // Fetch failure: the pinned copy renders in the panel and the last
  // good list stays in the dropdown (the app.js panel-error posture —
  // insert, never replace: the stream owns this body).
  const renderRunsError = (message) => {
    body.querySelector('.panel-error')?.remove();
    body.insertBefore(el('p', { class: 'panel-error', text: COPY.runsError(message) }), body.firstChild);
  };

  // CP10 client-side honor: every OPEN re-fetches — statuses freshly
  // derived, never cached. The in-flight guard only dedupes concurrent
  // fetches; a landed response never suppresses the next open's fetch
  // (no TTL, no memo, no staleness check).
  const refreshRuns = async () => {
    if (!alive() || runsFetching) return;
    runsFetching = true;
    runsSelect.replaceChildren(el('option', { text: COPY.loading, disabled: true })); // fetch pending
    try {
      const data = await fetchRunsList();
      const nowTs = data.now ? new Date(data.now).getTime() : null;
      if (Number.isFinite(nowTs)) serverNowTs = nowTs; // server stamps only (T-14-17) — same policy as hello
      lastRuns = Array.isArray(data.runs) ? data.runs : [];
      renderRunsOptions(lastRuns);
    } catch (err) {
      renderRunsError(err && err.message ? err.message : 'network error');
    } finally {
      runsFetching = false;
    }
  };

  // D-12: the ' · viewing' suffix tracks the displayed run — the last
  // good list re-renders on every displayed-run change (a RENDER cache
  // only; every open still re-fetches).
  const syncRunsViewing = () => {
    if (lastRuns) renderRunsOptions(lastRuns);
  };

  const bindRunsDropdown = () => {
    if (!runsSelect) return;
    runsSelect.addEventListener('click', refreshRuns); // every OPEN re-fetches (D-12)
    runsSelect.addEventListener('focus', refreshRuns); // keyboard opens land fresh too
    runsSelect.addEventListener('change', () => {
      if (!alive()) return;
      loadRun(runsSelect.value);
    });
  };

  // -- connect --------------------------------------------------------------
  // EventSource cannot send headers — the query param is the locked
  // 13 posture (T-14-18); the token never renders. The optional run is
  // 14-03's validated ?run= pin (loadRun reconnects); still exactly
  // ONE EventSource construction per page (T-14-20 posture).
  const connect = (token, run) => {
    const url = '/api/events?token=' + token
      + (run ? '&run=' + encodeURIComponent(run) : '');
    source = new EventSource(url);
    source.addEventListener('open', () => { setPill('connected'); });
    source.addEventListener('error', () => {
      if (source.readyState === EventSource.CLOSED) { renderTokenInvalid(); return; } // permanent (A6)
      setPill('reconnecting'); // transient drop: the last lines stay
    });
    source.addEventListener('hello', onHelloEvent);
    source.addEventListener('entry', onEntryEvent);
    source.addEventListener('switch', onSwitchEvent);
    source.addEventListener('notice', onNoticeEvent);
  };

  // -- boot -------------------------------------------------------------------
  const boot = () => {
    if (!viewport) return; // panels already replaced (token invalid)
    body.insertBefore(el('p', { class: 'loading', text: COPY.loading }), card);
    bindScroll();
    bindRunsDropdown();
    // app-shell port (context decision 3): the static banner-jump,
    // switch, follow, and filter-pill controls attach their click
    // listeners ONCE here, instead of a fresh listener per rendered
    // node — jumpToFirstError/resumeFollow/clearFilter are all defined
    // above by module-eval time, so the closures resolve correctly.
    bannerJumpBtn.addEventListener('click', jumpToFirstError);
    switchBtn.addEventListener('click', () => { if (switchTargetRun) loadRun(switchTargetRun); });
    pauseBtn.addEventListener('click', resumeFollow);
    filterBtn.addEventListener('click', clearFilter);
    setPill('connecting');
    connect(storedToken());
    refreshRuns(); // prime the dropdown once; every open re-fetches (D-12)
  };

  boot();
})();
