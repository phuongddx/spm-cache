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
  let tokenInvalid = false;
  let serverNowTs = null;
  let currentRun = null;
  let currentHeader = {};
  let cardPending = false;
  let ringCount = 0;
  let evicted = 0;
  let elisionEl = null;
  let follow = false;   // D-01: engages at replay completion, never mid-replay
  let replaying = false;
  let runEndInfo = null;

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
  const viewport = byId('log-viewport');
  const pill = byId('conn-pill');

  // -- token-invalid terminal page (the locked 13 sentence) -----------
  // A CLOSED EventSource is permanent (research A6): any non-200
  // kills reconnection, so auth-dead tabs must see a terminal state,
  // never a promise of reconnection.
  const renderTokenInvalid = () => {
    if (tokenInvalid) return;
    tokenInvalid = true;
    const main = document.querySelector('main.content');
    if (main) main.replaceChildren(el('p', { class: 'error-page', text: COPY.tokenInvalid }));
  };

  // -- connection pill (the panel's liveness marker) -------------------
  const setPill = (state) => {
    pill.textContent = COPY[state];
    pill.className = state === 'connected'
      ? 'conn-pill conn-pill-connected log-live'
      : `conn-pill${state === 'reconnecting' ? ' conn-pill-reconnecting' : ''}`;
  };

  // -- cold load + stream state (D-13) ---------------------------------
  const removeLoading = () => { body.querySelector('.loading')?.remove(); };

  const resetForRun = (name) => {
    currentRun = name;
    cardPending = true; // the replayed run_start header rebuilds the card (the switch path carries no fresh hello)
    viewport.replaceChildren();
    ringCount = 0;
    evicted = 0;
    elisionEl = null;
    runEndInfo = null;
    follow = false;      // D-13: follow engages at replay completion, never mid-replay
    replaying = true;
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
    const para = el('p', { class: 'empty-body' });
    para.append('Run ', el('span', { class: 'cmd', text: 'spm-cache build' }), ' to produce the first run log.');
    viewport.append(el('h3', { class: 'empty-title', text: COPY.noRunsTitle }), para);
  };

  // -- identity card (D-06) ---------------------------------------------
  // hello statuses: the server derivation is authoritative; a
  // 'completed' run's exact exit state (✓/✗) refines when its run_end
  // line replays — a missing run_end never derives completion.
  const statusKey = (status) => {
    if (status === 'failed') return 'failed';
    if (status === 'interrupted') return 'interrupted';
    if (status === 'success' || status === 'completed') return 'success';
    return 'running';
  };

  const setCardStatus = (key) => {
    const status = RUN_STATUS[key] || RUN_STATUS.running;
    statusEl.className = `log-status ${status.cls}`;
    statusEl.textContent = `${status.glyph} ${status.word}`;
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
    if (endIso) text += ` · completed ${relative(endIso)} ago`;
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
    if (!elisionEl) {
      elisionEl = el('div', { class: 'log-elision' });
      viewport.insertBefore(elisionEl, viewport.firstChild);
    }
    oldest.remove();
    ringCount -= 1;
    evicted += 1;
    elisionEl.textContent = COPY.elision(evicted);
  };

  const appendLine = (node) => {
    viewport.append(node);
    ringCount += 1;
    if (ringCount > RING_LIMIT) evictOldest();
  };

  // -- entry rendering, keyed ONLY on the parsed event field (T-12-01) ---
  const appendBody = (data) => {
    const raw = typeof data.text === 'string' ? data.text : '';
    const text = raw.replace(/\n$/, ''); // one trailing newline is framing, not content
    const isErr = data.stream === 'err';
    appendLine(el('div', {
      class: isErr ? 'log-line log-err' : 'log-line',
      text: isErr ? COPY.errPrefix + text : text, // ANSI codes are data — literal characters, no interpretation
    }));
  };

  const renderEntry = (data) => {
    if (data.event === 'run_start') {
      if (cardPending) buildCard(data, 'running');
      return; // no line — the card is its surface
    }
    if (data.event === 'run_end') {
      runEndInfo = data; // ended_at drives the completed-ago suffix
      renderTimes();
      return; // no line — the card (and the D-03 banner) is its surface
    }
    if (data.event === 'package_start' || data.event === 'phase') {
      appendLine(el('div', {
        class: 'log-line log-divider',
        text: COPY.divider(typeof data.name === 'string' ? data.name : ''),
      })); // dividers are the anchor targets; the rail chips land in 14-05
      return;
    }
    if (data.event === 'package_end' || data.event === 'sh') return; // no line
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
    const payload = parseData(e);
    if (!payload) return;
    const nowTs = payload.now ? new Date(payload.now).getTime() : null;
    if (Number.isFinite(nowTs)) serverNowTs = nowTs; // the only clock — re-derived on every hello
    removeLoading();
    if (!payload.run || payload.status === 'idle') { renderEmptyState(); return; }
    if (payload.run !== currentRun) {
      resetForRun(payload.run);
      buildCard(payload.header, statusKey(payload.status));
    } else {
      setCardStatus(statusKey(payload.status)); // reconnect: identity re-derived from disk per CP10
    }
  };

  const onEntryEvent = (e) => {
    const data = parseData(e);
    if (data) renderEntry(data);
  };

  const onNoticeEvent = (e) => {
    const data = parseData(e);
    if (data && typeof data.message === 'string') {
      appendLine(el('div', { class: 'log-line log-notice', text: COPY.notice(data.message) }));
    }
  };

  // D-04 seam: a new run's arrival switches the display — the entry
  // stream that follows replays the new file from byte 0 and its
  // run_start header rebuilds the card. The switch-notice bar and its
  // pinned-run control are 14-05 surfaces on the #log-switch slot.
  const onSwitchEvent = (e) => {
    const data = parseData(e);
    if (!data || typeof data.run !== 'string' || data.run === currentRun) return;
    resetForRun(data.run);
  };

  // -- connect --------------------------------------------------------------
  // EventSource cannot send headers — the query param is the locked
  // 13 posture (T-14-18); the token never renders.
  const connect = (token) => {
    source = new EventSource('/api/events?token=' + token);
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
    setPill('connecting');
    connect(sessionStorage.getItem(TOKEN_KEY));
  };

  boot();
})();
