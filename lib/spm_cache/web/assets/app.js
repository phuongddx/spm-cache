// spm-cache dashboard (Phase 13) — one vanilla ES module, no framework,
// no build step, fully offline (13-CONTEXT "Frontend Architecture").
// Stored-XSS defense (T-13-13): every dynamic string — package names,
// doctor messages, fix hints — is rendered through textContent only;
// this file never assigns markup strings to the DOM.
(() => {
  'use strict';

  // -- 1. token bootstrap (locked order: parse → store in session
  //    storage → clean the URL via the History API → render; the URL
  //    is clean before anything draws, so refreshes and Referers never
  //    carry the token) -------------------------------------------------
  const TOKEN_KEY = 'spm-cache-web-token';
  const bootToken = new URLSearchParams(window.location.search).get('token');
  if (bootToken) {
    sessionStorage.setItem(TOKEN_KEY, bootToken);
    window.history.replaceState(null, '', '/');
  }
  const token = sessionStorage.getItem(TOKEN_KEY);

  // -- 2. DOM helpers (textContent only — never markup strings) -------
  const byId = (id) => document.getElementById(id);
  const el = (tag, opts = {}) => {
    const node = document.createElement(tag);
    if (opts.class) node.className = opts.class;
    if (opts.text !== undefined) node.textContent = opts.text;
    if (opts.title) node.title = opts.title;
    return node;
  };

  // Status vocabularies (13-UI-SPEC locked). Table/graph states and
  // doctor verdicts share one color vocabulary.
  const STATUS_CLASS = { hit: 'ok', missed: 'warn', ignored: 'neutral', excluded: 'excluded', plugin: 'plugin' };
  const FIDELITY_CLASS = {
    'graph-pinned': 'ok', 'host-pinned': 'ok',
    'resolution-incompatible': 'warn', 'not-graph-pinned': 'neutral',
  };
  // Reason chips (16-UI-SPEC D-09, CP10): the read model derives the
  // word server-side; the client only maps it to an EXISTING badge
  // class — an unrecognised value renders verbatim in the neutral
  // class rather than being filtered or remapped.
  const REASON_CLASS = {
    'pattern-managed': 'neutral',
    plugin: 'plugin',
    'binary-target': 'neutral',
    excluded: 'excluded',
    fidelity: 'warn',
  };
  const COLS = ['Package', 'Config', 'Size', 'State', 'Fidelity', 'Cached'];
  const COL_CLASS = ['col-name', 'col-config', 'col-size', 'col-state', 'col-fidelity', 'col-cached'];

  // Stamps derive from SERVER timestamps, never client now() (T-13-16).
  const pad2 = (n) => String(n).padStart(2, '0');
  const fmtHMS = (iso) => {
    const d = new Date(iso);
    return `${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
  };

  const humanBytes = (n) => {
    if (!Number.isFinite(n) || n < 1024) return `${n} B`;
    const units = ['KB', 'MB', 'GB'];
    let value = n;
    let i = -1;
    do { value /= 1024; i += 1; } while (value >= 1024 && i < units.length - 1);
    return `${value.toFixed(1)} ${units[i]}`;
  };

  const panelError = (panel, message) =>
    `Couldn't load ${panel}: ${message}. Check that spm-cache web is still running, then Refresh.`;

  // -- 3. authed fetch layer -------------------------------------------
  const TOKEN_INVALID_COPY = "This page's access token is no longer valid. Restart spm-cache web and open the URL it prints.";
  let tokenInvalid = false;
  const renderTokenInvalid = () => {
    if (tokenInvalid) return;
    tokenInvalid = true;
    const main = document.querySelector('main.content');
    if (main) main.replaceChildren(el('p', { class: 'error-page', text: TOKEN_INVALID_COPY }));
  };

  const request = async (path) => {
    let res;
    try {
      res = await window.fetch(path, { headers: { 'X-SPM-Token': token } });
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
    return envelope;
  };

  // Panel errors keep last-good rows: the error line is only prepended
  // when the panel already shows rendered data (dataset.rendered === '1').
  const renderPanelError = (body, panel, message) => {
    body.querySelector('.panel-error')?.remove();
    const line = el('p', { class: 'panel-error', text: panelError(panel, message) });
    if (body.dataset.rendered === '1') {
      body.insertBefore(line, body.firstChild);
    } else {
      body.replaceChildren(line);
    }
  };

  // Empty state: heading + body with accent .cmd spans for commands.
  const renderEmpty = (body, heading, parts) => {
    const para = el('p', { class: 'empty-body' });
    parts.forEach((part) => { para.append(part); });
    body.dataset.rendered = '1';
    body.replaceChildren(el('h3', { class: 'empty-title', text: heading }), para);
  };
  const cmd = (text) => el('span', { class: 'cmd', text });

  // -- 4. state table renderer (DASH-01) --------------------------------
  const stateRow = (p) => {
    const row = el('tr');
    row.append(el('td', { class: 'col-name', title: p.name,
      text: p.has_macro ? `◆ ${p.name}` : p.name }));
    row.append(el('td', { class: 'col-config', text: p.config }));
    row.append(el('td', { class: 'mono col-size', text: humanBytes(p.size_bytes) }));
    const stateCell = el('td', { class: 'col-state' });
    if (p.state) {
      stateCell.append(el('span', { text: p.state,
        class: `badge badge-${STATUS_CLASS[p.state] || 'neutral'}` }));
    } else {
      stateCell.append(el('span', { class: 'state-empty', text: '—' }));
    }
    row.append(stateCell);
    const fidelity = p.fidelity || 'not-graph-pinned';
    row.append(el('td', { class: `mono col-fidelity fid-${FIDELITY_CLASS[fidelity] || 'neutral'}`,
      text: fidelity, title: fidelity }));
    // Toggle cell (D-01/D-02): checked/disabled are the row's OWN
    // saved_cached/toggleable fields, verbatim — no client derivation
    // (CP10). The accessible name carries the RAW name (no ◆ prefix,
    // A10); el() does not cover input attributes, so this cell is
    // built with the DOM API directly.
    const toggleCell = el('td', { class: 'col-cached' });
    const checkbox = document.createElement('input');
    checkbox.type = 'checkbox';
    checkbox.checked = p.saved_cached;
    checkbox.disabled = !p.toggleable;
    checkbox.setAttribute('aria-label', `Toggle caching for ${p.name}`);
    checkbox.addEventListener('change', () => postToggle(p.name, checkbox.checked));
    toggleCell.append(checkbox);
    if (!p.toggleable && p.reason) {
      toggleCell.append(el('span', {
        class: `badge badge-${REASON_CLASS[p.reason] || 'neutral'}`,
        text: p.reason, title: p.reason,
      }));
    }
    if (p.pending) {
      toggleCell.append(el('span', { class: 'badge badge-neutral', text: 'pending', title: 'pending' }));
    }
    row.append(toggleCell);
    return row;
  };

  const renderState = (envelope) => {
    const data = envelope.data;
    const body = byId('state-body');
    byId('state-stamp').textContent =
      `Updated ${fmtHMS(envelope.generated_at)} · auto-refresh ${pollSeconds}s`;
    if (!data.packages || data.packages.length === 0) {
      renderEmpty(body, 'No cached packages yet', ['Run ', cmd('spm-cache build'),
        ' to populate the cache, then Refresh.']);
      return;
    }
    const table = el('table', { class: 'state-table' });
    const headRow = el('tr');
    COLS.forEach((h, i) => { headRow.append(el('th', { class: COL_CLASS[i], text: h })); });
    const thead = el('thead');
    thead.append(headRow);
    table.append(thead);
    const tbody = el('tbody');
    data.packages.forEach((p) => { tbody.append(stateRow(p)); });
    table.append(tbody);
    body.dataset.rendered = '1';
    body.replaceChildren(table);
    showToggleFailure(body);
  };

  // -- 5/6. state loading + auto-poll (failed polls never stop the loop) -
  let pollSeconds = 5;

  const refreshState = async () => {
    const btn = byId('state-refresh');
    btn.disabled = true;
    try {
      const envelope = await request('/api/state');
      pollSeconds = envelope.data.poll_seconds || 5;
      renderState(envelope);
    } catch (err) {
      if (!tokenInvalid) renderPanelError(byId('state-body'), 'Cache State', err.message);
    } finally {
      btn.disabled = false;
    }
  };

  // -- 8. doctor panel (DASH-02) — on-demand only, never auto-polled ----
  const MARKER = { ok: '✓', warn: '!', fail: '✗' };

  const renderDoctor = (envelope) => {
    const data = envelope.data;
    const body = byId('doctor-body');
    if (!data.has_run) {
      byId('doctor-stamp').textContent = '';
      renderEmpty(body, 'Doctor has not run yet',
        ['Select Run Doctor to check your environment.']);
      return;
    }
    byId('doctor-stamp').textContent =
      `Cached — generated at ${fmtHMS(envelope.generated_at)}`;
    const wrap = el('div', { class: 'checks' });
    data.checks.forEach((check) => {
      const line = el('div', { class: 'check-line' });
      line.append(el('span', {
        class: `check-marker check-marker-${check.status}`,
        text: MARKER[check.status] || '·',
      }));
      line.append(el('span', { class: 'check-name', text: check.name, title: check.name }));
      line.append(el('span', { class: 'check-message', text: check.message, title: check.message }));
      wrap.append(line);
      if (check.status !== 'ok' && check.fix_hint) {
        wrap.append(el('p', { class: 'fix-hint', text: `↳ ${check.fix_hint}` }));
      }
    });
    const summary = data.summary || {};
    wrap.append(el('p', { class: 'check-summary',
      text: `${summary.ok} ok · ${summary.warnings} warnings · ${summary.failures} failures` }));
    body.dataset.rendered = '1';
    body.replaceChildren(wrap);
  };

  const doctorRequest = async (run) => {
    const btn = byId('doctor-run');
    if (!btn) return; // panels already replaced (token invalid)
    btn.disabled = true;
    if (run) btn.textContent = 'Running…';
    try {
      renderDoctor(await request(run ? '/api/doctor?run=1' : '/api/doctor'));
    } catch (err) {
      if (!tokenInvalid) renderPanelError(byId('doctor-body'), 'Doctor', err.message);
    } finally {
      btn.disabled = false;
      if (run) btn.textContent = 'Run Doctor';
    }
  };

  // -- 9. graph panel (DASH-03) — vendored cytoscape, nodes only --------
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const fmtGraphStamp = (iso) => {
    const d = new Date(iso);
    return `${MONTHS[d.getMonth()]} ${d.getDate()}, ${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
  };

  const NODE_COLOR = { hit: '#4CAF50', missed: '#FF9800', ignored: '#9E9E9E',
    excluded: '#607D8B', plugin: '#3F51B5', macro: '#9C27B0' };

  const graphStyle = [
    { selector: 'node', style: { label: 'data(module)', color: '#E6EDF3',
      'font-size': '12px', 'text-valign': 'center', width: '40px', height: '40px' } },
    ...Object.keys(NODE_COLOR).filter((k) => k !== 'macro')
      .map((k) => ({ selector: `node[status="${k}"]`,
        style: { 'background-color': NODE_COLOR[k] } })),
    { selector: 'node[hasMacro="true"]',
      style: { shape: 'diamond', 'background-color': NODE_COLOR.macro } },
  ];

  const renderLegend = () => {
    const legend = byId('graph-legend');
    legend.replaceChildren();
    Object.keys(NODE_COLOR).forEach((key) => {
      const item = el('span', { class: 'legend-item' });
      const swatch = el('span', { class: 'legend-swatch' });
      swatch.style.backgroundColor = NODE_COLOR[key];
      item.append(swatch, key);
      legend.append(item);
    });
  };

  // Panel-scoped cytoscape handle (review IN-01): null until the first
  // graph render, destroyed and re-created on every Refresh.
  let cyGraph = null;

  const renderGraph = (envelope) => {
    const data = envelope.data;
    const body = byId('graph-body');
    if (!data.present) {
      byId('graph-stamp').textContent = '';
      renderEmpty(body, 'No dependency graph yet', ['Run ', cmd('spm-cache use'),
        ' to generate graph.json, then Refresh.']);
      return;
    }
    byId('graph-stamp').textContent =
      `Updated ${fmtGraphStamp(data.graph_generated_at)} · generated by spm-cache use`;
    byId('graph-wrap').hidden = false;
    body.querySelector('.loading')?.remove();
    if (data.nodes.length === 0) {
      body.insertBefore(el('p', { class: 'loading', text: 'No dependency graph yet' }),
        byId('graph-wrap'));
    }
    renderLegend();
    // One cytoscape instance for the tab's lifetime (review IN-01):
    // re-rendering without destroying the previous instance stacks
    // canvases, listeners, and graph objects inside the container.
    if (cyGraph) cyGraph.destroy();
    // Elements are the server's cytoscape node objects AS-SERVED — the
    // raw-entries-to-elements transform already happened server-side.
    cyGraph = window.cytoscape({
      container: byId('cy-canvas'),
      elements: data.nodes,
      style: graphStyle,
      layout: { name: 'grid' },
    });
    body.dataset.rendered = '1';
  };

  const loadGraph = async () => {
    const btn = byId('graph-refresh');
    if (!btn) return; // panels already replaced (token invalid)
    btn.disabled = true;
    try {
      renderGraph(await request('/api/graph'));
    } catch (err) {
      if (!tokenInvalid) renderPanelError(byId('graph-body'), 'Dependency Graph', err.message);
    } finally {
      btn.disabled = false;
    }
  };

  // -- 7. package toggle (Phase 16 — TOGL-01/02/03) ---------------------
  // Instant persist per row (D-08): no busy state, no per-row disable on
  // click — the checkbox stays live and a rapid second flip is a
  // legitimate second POST. Poll integrity (A8): the in-flight COUNTER
  // (not a boolean — a second flip while the first POST is still out
  // must not unskip the poll early) keeps the 5s cycle from redrawing
  // the table — and its stamp — out from under a checkbox the user
  // just changed. The failure line is a SEPARATE node from the panel's
  // own fetch-error line (T-16-26) so a rejected write and a failed
  // poll can never silently replace one another; it survives every
  // render until the next successful mutation or an explicit Refresh
  // clears it (prohibitions 12/13).
  let toggleInFlight = 0;
  let toggleFailure = '';
  const toggleFailureCopy = (name, message) =>
    `Couldn't save the toggle for ${name}: ${message}. Check that spm-cache web is still running, then try again.`;
  const showToggleFailure = (body) => {
    body.querySelector('.toggle-failure')?.remove();
    if (!toggleFailure) return;
    body.insertBefore(el('p', { class: 'toggle-failure', text: toggleFailure }), body.firstChild);
  };
  const clearToggleFailure = () => {
    toggleFailure = '';
    showToggleFailure(byId('state-body'));
  };
  const postToggle = (name, cached) => {
    toggleInFlight += 1;
    requestPost('/api/toggle', { package: name, cached }).then((ans) => {
      if (ans.status === 401 || ans.status === 403) return; // the token-invalid page owns the tab
      if (ans.ok) { clearToggleFailure(); return; }
      const data = (ans.envelope || {}).data || {};
      toggleFailure = toggleFailureCopy(name, data.message || `HTTP ${ans.status}`);
      showToggleFailure(byId('state-body'));
    }).finally(() => { toggleInFlight -= 1; });
  };

  // -- 10. initial render -------------------------------------------------
  const boot = () => {
    byId('port-label').textContent = `127.0.0.1:${window.location.port}`;
    byId('state-refresh').addEventListener('click', () => { clearToggleFailure(); refreshState(); });
    byId('doctor-run').addEventListener('click', () => doctorRequest(true));
    byId('graph-refresh').addEventListener('click', loadGraph);
    const loop = async () => {
      if (!byId('state-body')) return; // panels replaced (token invalid)
      // A8: skip the redraw (and its stamp) while a toggle POST is in
      // flight — Refresh (above) bypasses this by calling refreshState
      // directly, never through this loop.
      if (toggleInFlight === 0) await refreshState();
      window.setTimeout(loop, pollSeconds * 1000);
    };
    loop();
    doctorRequest(false);
    loadGraph();
  };


  // -- 11. build controls (Phase 15 — BLD-01/02/04) ----------------------
  // The copy table owns every row string (15-UI-SPEC); 'wait' is
  // byte-identical to the Installer's frozen announce (14-02 D-05).
  const CTRL = {
    busy: 'A build or rollback is already running — wait for it to finish.',
    wait: 'Waiting for build lock…',
    inflight: { build: 'Building…', rebuild: 'Rebuilding all…', rollback: 'Restoring source mode…' },
    failure: (name, message) => `Couldn't start the ${name}: ${message}. Check that spm-cache web is still running, then try again.`,
  };
  const ctl = { build: byId('ctl-build'), rebuild: byId('ctl-rebuild'), rollback: byId('ctl-rollback') };
  const row = byId('build-controls');
  const msg = byId('ctl-message');
  let verb = null; // the in-flight verb — progress events retune its message

  // request()'s POST twin: answers {ok, status, envelope} instead of
  // raising, so a 409 busy is branchable from a failure at the call
  // site (Pitfall 8); 401/403 keeps the shared token-invalid page.
  const requestPost = async (path, body) => {
    let res;
    try {
      res = await window.fetch(path, { method: 'POST',
        headers: { 'X-SPM-Token': token, 'Content-Type': 'application/json' },
        body: JSON.stringify(body) });
    } catch (err) {
      return { ok: false, status: 0, envelope: { data: { message: `network error (${err.message})` } } };
    }
    if (res.status === 401 || res.status === 403) {
      renderTokenInvalid();
      return { ok: false, status: res.status };
    }
    const envelope = await res.json().catch(() => ({ status: 'error', data: { message: `HTTP ${res.status}` } }));
    return { ok: res.ok && envelope.status !== 'error', status: res.status, envelope };
  };

  // The row state machine: every transition sets the disabled state
  // and the message together (no silent holds, prohibition 9), and
  // disabled derives ONLY from this tab's own POST or in-flight run —
  // never from lock data (A3).
  const say = (text, error) => {
    msg.hidden = !text;
    msg.textContent = text;
    msg.className = error ? 'ctl-message ctl-error' : 'ctl-message';
  };
  const freeze = (on) => { Object.values(ctl).forEach((b) => { b.disabled = on; }); };

  const settle = (name, ans) => {
    if (ans.status === 401 || ans.status === 403) return; // the token-invalid page owns the tab
    const data = (ans.envelope || {}).data || {};
    if (ans.status === 409) { freeze(false); verb = null; say(CTRL.busy, true); return; }
    if (!ans.ok) { freeze(false); verb = null; say(CTRL.failure(name, data.message || `HTTP ${ans.status}`), true); return; }
    freeze(true);
    verb = name;
    if (data.lock && data.lock.state === 'held') say(CTRL.wait); // entry assist: the spawn answer's lock snapshot, no poll (D-06)
    else say(CTRL.inflight[name]);
  };
  const clickBuild = (scope) => {
    freeze(true); // the double-submit guard disables before the request resolves
    say(CTRL.inflight[scope]);
    requestPost('/api/build', { scope }).then((ans) => settle(scope, ans));
  };
  ctl.build.addEventListener('click', () => clickBuild('build'));
  ctl.rebuild.addEventListener('click', () => clickBuild('rebuild'));

  // Two-step inline confirm (D-08/A6): Rollback arms the bar and
  // focus lands on Cancel — the safe default; Cancel restores the row
  // and returns focus. No dialogs anywhere (prohibition 3).
  const bar = byId('build-confirm');
  const barConfirm = byId('ctl-confirm');
  const barCancel = byId('ctl-cancel');
  const disarmBar = () => { bar.hidden = true; row.hidden = false; };
  ctl.rollback.addEventListener('click', () => {
    row.hidden = true;
    bar.hidden = false;
    barCancel.focus();
  });
  barCancel.addEventListener('click', () => { disarmBar(); ctl.rollback.focus(); });
  barConfirm.addEventListener('click', () => {
    barConfirm.disabled = true; // the bar's own double-submit guard
    barCancel.disabled = true;
    requestPost('/api/rollback', {}).then((ans) => {
      disarmBar(); // 2xx and rejection both collapse back into the row
      barConfirm.disabled = false;
      barCancel.disabled = false;
      settle('rollback', ans);
    });
  });

  // The A10 coupling: log.js publishes displayed-run milestones as one
  // spm-run-progress DOM CustomEvent; waiting/active retune the
  // in-flight message from the run's own bytes, ended returns the row
  // to idle so a retry is one click (A7). No second stream, no timer.
  document.addEventListener('spm-run-progress', (e) => {
    const phase = e.detail && e.detail.phase;
    if (phase === 'ended') { freeze(false); verb = null; say(''); return; }
    if (!verb) return; // an idle row renders nothing — the flavor is UI-run-scoped (A3)
    if (phase === 'waiting') say(CTRL.wait);
    if (phase === 'active') say(CTRL.inflight[verb]);
  });
  boot();
})();
