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
  const COLS = ['Package', 'Config', 'Size', 'State', 'Fidelity'];
  const COL_CLASS = ['col-name', 'col-config', 'col-size', 'col-state', 'col-fidelity'];

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
    return row;
  };

  const renderState = (envelope) => {
    const data = envelope.data;
    const body = byId('state-body');
    byId('state-stamp').textContent =
      `Updated ${fmtHMS(envelope.generated_at)} · auto-refresh ${pollSeconds}s`;
    if (!data.packages || data.packages.length === 0) {
      renderEmpty(body, 'No cached packages yet', ['Run ', cmd('spm-cache build'),
        ' to populate the cache, then ', cmd('Refresh'), '.']);
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

  // -- 7. initial render -------------------------------------------------
  const boot = () => {
    byId('port-label').textContent = `127.0.0.1:${window.location.port}`;
    byId('state-refresh').addEventListener('click', refreshState);
    const loop = async () => {
      await refreshState();
      window.setTimeout(loop, pollSeconds * 1000);
    };
    loop();
  };

  boot();
})();
