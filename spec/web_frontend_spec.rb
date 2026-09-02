# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

require_relative 'support/web_server_boot'

# Plan 13-03 (ported 2026-09 to the Grok-palette app-shell) — the
# dashboard frontend, pinned as SERVED and FILE bytes. This repo runs
# no JavaScript in CI: every contract below is a byte-level pin (the
# HTML the server serves, the asset files' exact contents), cross-checked
# by the manual browser walkthrough in the port's plan. Copy strings,
# color values, and the DOM-id contract are BINDING.
RSpec.describe 'spm-cache web dashboard frontend (app-shell port)' do
  let(:asset_dir) { SPMCache::Web::Assets::DEFAULT_ROOT }
  let(:index_html) { File.read(File.join(asset_dir, 'index.html')) }
  let(:styles_css) { File.read(File.join(asset_dir, 'styles.css')) }
  let(:app_js) { File.read(File.join(asset_dir, 'app.js')) }
  let(:cytoscape_js) { File.read(File.join(asset_dir, 'cytoscape.min.js')) }

  def with_dashboard_server(&block)
    Dir.mktmpdir do |project_dir|
      WebServerBoot.with_server(
        project_dir: project_dir, assets: SPMCache::Web::Assets.new, &block
      )
    end
  end

  def served(path, headers = {})
    res = nil
    with_dashboard_server do |handle|
      res = WebServerBoot.http_get(handle, path, headers)
    end
    res
  end

  describe 'served index (GET /?token=)' do
    it 'serves 200 text/html with the exact index.html bytes' do
      res = served('/?token=anything')
      expect(res.code).to eq('200')
      expect(res['Content-Type']).to eq('text/html')
      expect(res.body).to eq(File.binread(File.join(asset_dir, 'index.html')))
    end

    it 'carries the page title and the four surface titles in locked DOM order' do
      expect(index_html).to include('<title>spm-cache</title>')
      expect(index_html).to include('<h2 class="surface-title">Run Log</h2>')
      expect(index_html).to include('<h2 class="surface-title">Cache State</h2>')
      expect(index_html).to include('<h2 class="surface-title">Doctor</h2>')
      expect(index_html).to include('<h2 class="surface-title">Dependency Graph</h2>')
      expect(index_html.index('Run Log')).to be < index_html.index('Cache State')
      expect(index_html.index('Cache State')).to be < index_html.index('>Doctor<')
      expect(index_html.index('>Doctor<')).to be < index_html.index('Dependency Graph')
    end

    it 'build controls live in the topbar: Build/Rebuild all/Rollback, plus per-surface Refresh/Run Doctor' do
      expect(index_html).to include('<button type="button" class="btn btn-primary" id="ctl-build">Build</button>')
      expect(index_html).to include('<button type="button" class="btn btn-quiet" id="ctl-rebuild">Rebuild all</button>')
      expect(index_html).to include('id="ctl-rollback">Rollback</button>')
      expect(index_html.scan(%r{<button[^>]*>Refresh</button>}).size).to eq(2) # Cache State + Dependency Graph
      expect(index_html.scan(%r{<button[^>]*>Run Doctor</button>}).size).to eq(1)
    end

    it 'each surface carries a stamp span (Cache State/Doctor/Graph); Doctor and Graph bodies start with a muted Loading… line' do
      expect(index_html.scan(/class="stamp"/).size).to eq(3)
      expect(index_html.scan(%r{<p class="loading">Loading…</p>}).size).to eq(2) # doctor-body + graph-body — state-body has no cold-loading line, it starts with real (possibly empty) static chrome
    end

    it 'references exactly three RELATIVE assets: assets/styles.css, assets/cytoscape.min.js, assets/app.js (module)' do
      expect(index_html).to include('href="assets/styles.css"')
      expect(index_html).to include('src="assets/cytoscape.min.js"')
      expect(index_html).to include('type="module"')
      expect(index_html).to include('src="assets/app.js"')
      # Relative ONLY: no leading-slash paths, no protocol-relative URLs,
      # no scheme-absolute references anywhere in the document.
      expect(index_html).not_to match(%r{(?:src|href)=["']/})
      expect(index_html).not_to match(%r{(?:src|href)=["']//})
      expect(index_html).not_to match(/https?:/i)
    end

    it 'loads cytoscape BEFORE app.js so window.cytoscape exists at render time' do
      expect(index_html.index('cytoscape.min.js')).to be < index_html.index('app.js')
    end

    it 'graph surface body carries the canvas mount and the legend element, ungated by hidden (decision 6)' do
      expect(index_html).to include('id="graph-legend"')
      expect(index_html).to include('id="cy-canvas"')
      expect(index_html).to match(/<div class="graph-wrap" id="graph-wrap">/) # no `hidden` attribute — starts visible
    end

    it 'ships zero OpenDesign mockup artifacts: no data-od-id, no demo.js reference, no "Static preview" note' do
      expect(index_html).not_to include('data-od-id')
      expect(index_html).not_to include('demo.js')
      expect(index_html).not_to include('Static preview')
    end

    it 'carries every id from the 42-entry DOM-id contract app.js/log.js query via getElementById' do
      contract_ids = %w[
        port-label conn-pill log-runs runs-slot
        build-controls ctl-build ctl-rebuild ctl-rollback ctl-message
        build-confirm ctl-cancel ctl-confirm
        log-body log-card log-status log-trigger log-command log-config
        log-started log-argv log-runid log-banner log-switch
        log-viewport log-overlay rail-phases rail-packages
        state-body state-stamp state-refresh sync-apply sync-message sync-revert
        doctor-body doctor-stamp doctor-run
        graph-body graph-stamp graph-refresh graph-wrap graph-legend cy-canvas
      ]
      missing = contract_ids.reject { |id| index_html.include?(%(id="#{id}")) }
      expect(missing).to eq([])
    end

    it 'carries the app-shell IDs this port introduced: nav rail, surfaces, cold-load-honest new controls' do
      new_ids = %w[
        rail alert-rail surface-main surface-run surface-cache surface-doctor surface-graph
        topbar-state runstat-cmd log-banner-text log-banner-jump log-switch-btn
        log-filter-pill log-count log-follow-btn state-filter state-total state-empty
        chip-n-all doctor-summary check-list rail-badge-cache rail-badge-doctor
      ]
      missing = new_ids.reject { |id| index_html.include?(%(id="#{id}")) }
      expect(missing).to eq([])
    end
  end

  describe 'app-shell layout (topbar / alert-rail / nav-rail / 4 surfaces, cold-load honesty)' do
    it 'the shell is a topbar + alert-rail + (nav-rail, surface-main) grid; Run Log ships is-active/visible by default' do
      expect(index_html).to include('<div class="app">')
      expect(index_html).to include('<div class="alert-rail" id="alert-rail">')
      expect(index_html).to include('<nav class="rail" id="rail" aria-label="Dashboard surfaces">')
      expect(index_html).to include('<section class="surface is-active" id="surface-run" data-surface="run" aria-label="Run Log">')
      %w[cache doctor graph].each do |name|
        expect(index_html).to match(/<section class="surface" id="surface-#{name}" data-surface="#{name}" aria-label="[^"]+" hidden>/)
      end
    end

    it 'nav-rail carries exactly four data-surface items in run/cache/doctor/graph order' do
      surfaces = index_html.scan(/data-surface="(\w+)"/).flatten
      # every rail-item AND every surface section carries data-surface —
      # the rail's four items lead, the four <section>s follow in the same order
      expect(surfaces.first(4)).to eq(%w[run cache doctor graph])
      expect(surfaces.last(4)).to eq(%w[run cache doctor graph])
    end

    it 'deletes the fabricated progress meter entirely — no #meter-fill/#runstat-count/#runstat-elapsed nodes, no packages_total data to back them' do
      %w[meter-fill runstat-count runstat-elapsed].each do |id|
        expect(index_html).not_to include(%(id="#{id}"))
      end
      expect(index_html).not_to match(/class="meter"/)
    end

    it 'deletes the fabricated rail-facts block (Cache/Hit rate/Saved) — no backing data exists in the wire contract' do
      expect(index_html).not_to include('rail-facts')
    end

    it 'cold-load: topbar state pill, command mirror, port label, and log identity card carry NO fabricated values' do
      expect(index_html).to match(%r{<span class="state-pill state-idle" id="topbar-state"></span>})
      expect(index_html).to match(%r{<span class="runstat-cmd mono" id="runstat-cmd"></span>})
      expect(index_html).to match(%r{<span class="port-label" id="port-label"></span>})
      expect(index_html).not_to include('Running</span>')
      expect(index_html).not_to include('spm-cache build</span>')
    end

    it 'cold-load: #log-runs ships empty (real options come from refreshRuns()); no fake run history baked in' do
      expect(index_html).to match(%r{<select class="log-runs-select" id="log-runs"></select>})
    end

    it 'cold-load: #doctor-summary starts hidden and empty; no hardcoded tallies' do
      expect(index_html).to match(%r{<div class="doctor-summary" id="doctor-summary" hidden></div>})
      expect(index_html).not_to match(%r{\d+</b> failed})
    end

    it 'cold-load: rail badges (#rail-badge-cache/#rail-badge-doctor) ship hidden and empty — no fabricated counts or glyphs' do
      expect(index_html).to match(%r{<span class="rail-count" id="rail-badge-cache" hidden></span>})
      expect(index_html).to match(%r{<span class="rail-status" id="rail-badge-doctor" hidden></span>})
    end

    it '#log-card no longer starts hidden and holds neutral cold-load placeholder text, never fabricated identity data' do
      expect(index_html).to match(/<div class="log-card" id="log-card">/) # no `hidden` attribute
      expect(index_html).to match(%r{<span class="log-status" id="log-status">Loading…</span>})
      expect(index_html).to match(%r{<span class="badge badge-neutral" id="log-trigger"></span>})
      expect(index_html).to match(%r{<span class="log-command mono" id="log-command"></span>})
    end

    it '#graph-wrap no longer starts hidden (decision 6) — the .loading placeholder covers the cold empty canvas honestly' do
      graph_body = index_html[%r{<div class="surface-body" id="graph-body">.*?</section>}m]
      expect(graph_body.index('class="loading"')).to be < graph_body.index('id="graph-wrap"')
    end

    it 'the log-banner/log-switch/follow-pill/filter-pill move to static markup-with-real-wiring (context decision 3)' do
      expect(index_html).to include('<span class="log-banner-text" id="log-banner-text"></span>')
      expect(index_html).to include('<button type="button" class="btn btn-quiet btn-sm" id="log-banner-jump">Jump to first error</button>')
      expect(index_html).to match(%r{<button type="button" class="btn btn-quiet btn-sm log-runid-btn" id="log-switch-btn"></button>})
      expect(index_html).to match(%r{<button type="button" class="log-pill-btn" id="log-follow-btn" hidden>↓ Resume follow</button>})
      expect(index_html).to match(%r{<button type="button" class="log-pill-btn log-filter-pill mono" id="log-filter-pill" hidden></button>})
    end

    it 'the unsaved-changes bar (#state-sync-bar) is static show/hide with distinct honesty-sentence and feedback-message nodes (context decision 4)' do
      bar = index_html[%r{<div class="state-sync-bar"[\s\S]*?</div>\s*</div>}]
      expect(bar).to include('id="state-sync-bar"')
      expect(bar).to include('hidden')
      expect(bar).to include(
        'Changes are saved but not applied yet. spm-cache.yml is rewritten on every change — '\
        'hand-written comments in the file are not preserved.'
      )
      expect(bar).to include('id="sync-revert">Revert all</button>')
      expect(bar).to include('id="sync-apply">Apply now</button>')
      expect(bar).to match(%r{<span class="ctl-message" id="sync-message" aria-live="polite" hidden></span>})
      # the honesty sentence has NO id — app.js/saySync() must never be
      # able to clobber it via byId('sync-message'); they are separate nodes
      expect(bar).not_to match(/state-sync-text" id=/)
    end

    it 'preserves the load-bearing [hidden] rule and the display:flex overrides it must outrank' do
      expect(styles_css).to match(/\[hidden\]\s*\{\s*display: none !important;\s*\}/)
      %w[.log-banner .build-confirm .state-sync-bar .log-switch].each do |sel|
        block = styles_css[/#{Regexp.escape(sel)}[,\s][\s\S]*?\{[^}]*\}/]
        expect(block).to match(/display: flex/)
      end
    end
  end

  describe 'offline gate (SC3 — first-party assets only)' do
    it 'index.html and styles.css carry zero scheme-absolute URLs' do
      expect(index_html).not_to match(%r{https?://}i)
      expect(styles_css).not_to match(%r{https?://}i)
    end

    it 'index.html and styles.css carry zero cdn. references' do
      expect(index_html).not_to match(/cdn\./i)
      expect(styles_css).not_to match(/cdn\./i)
    end

    it 'app.js carries zero scheme-absolute URLs and zero cdn. references' do
      expect(app_js).not_to match(%r{https?://}i)
      expect(app_js).not_to match(/cdn\./i)
    end
  end

  describe 'app.js source contract — token bootstrap (locked)' do
    it 'moves the token from the URL to sessionStorage, then cleans the URL BEFORE first render' do
      setitem_at = app_js.index(/sessionStorage\.setItem\(/)
      replace_at = app_js.index(/history\.replaceState\(/)
      boot_at = app_js.index(/boot\(\);/)
      expect(setitem_at).to be < replace_at
      expect(replace_at).to be < boot_at
    end

    it 'sends X-SPM-Token on every request' do
      expect(app_js).to include("'X-SPM-Token': token")
    end

    it 'never writes the token into the DOM (T-13-15)' do
      expect(app_js).not_to match(/el\([^)]*token/)
      expect(app_js).not_to match(/textContent\s*=\s*[^;]*token/)
    end
  end

  describe 'app.js source contract — fetch layer + 401/403' do
    it 'renders the full-page token-invalid copy, replacing the whole app shell (topbar+alert-rail+shell), not just the panels' do
      expect(app_js)
        .to include("This page's access token is no longer valid. Restart spm-cache web and open the URL it prints.")
      expect(app_js).to include("document.querySelector('.app')")
    end

    it 'consumes the {status,data} envelope and throws the server message' do
      expect(app_js).to include("envelope.status === 'error'")
      expect(app_js).to include('envelope.data && envelope.data.message')
    end
  end

  describe 'app.js source contract — state table + filter/chips (app-shell port)' do
    it 'renders rows ONLY into #state-rows — the <thead>, filter/chip toolbar and sync bar are static markup untouched by JS' do
      expect(app_js).to include("byId('state-rows')")
      expect(app_js).not_to include('COLS')
      expect(app_js).not_to match(/el\('thead'/)
      expect(app_js).not_to match(/el\('th'/)
    end

    it 'pins the status→class vocabulary exactly' do
      expect(app_js).to include("hit: 'ok', missed: 'warn', ignored: 'neutral', excluded: 'excluded', plugin: 'plugin'")
    end

    it 'prefixes macro packages with ◆ in the name cell' do
      expect(app_js).to include('◆ ${p.name}')
    end

    it 'renders state null as a muted plain dash, never a badge' do
      expect(app_js).to include("'—'")
      expect(app_js).to include('p.state')
    end

    it 'sizes are human-formatted with one decimal in KB/MB/GB' do
      expect(app_js).to include("'KB', 'MB', 'GB'")
      expect(app_js).to include('toFixed(1)')
    end

    it 'fidelity colors per the locked mapping' do
      expect(app_js).to include("'graph-pinned': 'ok', 'host-pinned': 'ok'")
      expect(app_js).to include("'resolution-incompatible': 'warn'")
      expect(app_js).to include("'not-graph-pinned': 'neutral'")
    end

    it 'lastPackages caches the last successful fetch — the filter/chip handlers re-render from it without a new request' do
      expect(app_js).to include('let lastPackages = [];')
      expect(app_js).to include('lastPackages = data.packages || [];')
      render_rows = app_js[/const renderStateRows = \(\) => \{[\s\S]*?\n  \};/]
      expect(render_rows).to include('lastPackages.forEach')
    end

    it 'packageVisible filters on substring name match AND the active state chip (hit/missed/other = neither hit nor missed)' do
      pv = app_js[/const packageVisible = \(p\) => \{[\s\S]*?\n  \};/]
      expect(pv).to include('p.name.toLowerCase().includes(stateFilterText)')
      expect(pv).to include("stateFilterChip === 'hit'")
      expect(pv).to include("stateFilterChip === 'missed'")
      expect(pv).to include("p.state !== 'hit' && p.state !== 'missed'")
    end

    it '#state-empty is the FILTER-yields-zero-rows indicator only — a genuinely empty cache renders an honest empty table, no fabricated copy' do
      render_rows = app_js[/const renderStateRows = \(\) => \{[\s\S]*?\n  \};/]
      expect(render_rows).to include("byId('state-empty').hidden = !(lastPackages.length > 0 && shown === 0);")
    end

    it '#chip-n-all and #state-total are derived from the real lastPackages array — hit/missed counts + humanBytes total' do
      render_rows = app_js[/const renderStateRows = \(\) => \{[\s\S]*?\n  \};/]
      expect(render_rows).to include("byId('chip-n-all').textContent = String(lastPackages.length);")
      expect(render_rows).to include("p.state === 'hit'")
      expect(render_rows).to include("p.state === 'missed'")
      expect(render_rows).to include('humanBytes(totalBytes)')
    end

    it '#state-filter input and .chip-group .chip clicks re-render rows without a new fetch' do
      expect(app_js).to include("byId('state-filter').addEventListener('input'")
      expect(app_js).to include("querySelectorAll('.chip-group .chip')")
      expect(app_js).to include("chipEl.classList.add('is-on')")
    end

    it '#rail-badge-cache mirrors the real pending count — never fabricated, derived after every successful /api/state fetch' do
      badge = app_js[/const updateCacheBadge = \(pendingCount\) => \{[\s\S]*?\n  \};/]
      expect(badge).to include("byId('rail-badge-cache')")
      expect(badge).to include('badge.hidden = pendingCount === 0;')
      render_state = app_js[/const renderState = \(envelope\) => \{[\s\S]*?\n  \};/]
      expect(render_state).to include('lastPackages.filter((p) => p.pending).length')
      expect(render_state).to include('updateCacheBadge(pendingCount);')
    end
  end

  describe 'app.js source contract — polling, stamps, errors' do
    it 'polls /api/state at data.poll_seconds with a 5s fallback' do
      expect(app_js).to include("'/api/state'")
      expect(app_js).to include('poll_seconds || 5')
    end

    it 'stamp format: Updated {HH:MM:SS} · auto-refresh {N}s (server time, middot)' do
      expect(app_js).to match(/Updated \$\{fmtHMS\([^)]*\)\} · auto-refresh \$\{pollSeconds\}s/)
      expect(app_js).to include('padStart(2')
    end

    it 'panel error copy is the exact Couldn’t-load sentence' do
      expect(app_js)
        .to include("Couldn't load ${panel}: ${message}. Check that spm-cache web is still running, then Refresh.")
    end

    it 'a failed poll keeps the last rows (error line prepends, never replaces)' do
      expect(app_js).to include('dataset.rendered')
      expect(app_js).to include('insertBefore')
    end

    it 'the poll loop never stops: failures are caught and the next tick is always scheduled' do
      expect(app_js).to include('window.setTimeout(loop')
    end

    it 'refresh buttons disable while in flight (label unchanged, no spinners)' do
      expect(app_js).to include('btn.disabled = true')
      expect(app_js).to include('btn.disabled = false')
    end

    it 'stamps derive from server timestamps, never client now() (T-13-16)' do
      expect(app_js).not_to include('Date.now()')
      expect(app_js).to include('new Date(iso)')
    end

    it 'fills the port label as 127.0.0.1:{port}' do
      expect(app_js).to include('127.0.0.1:${window.location.port}')
    end
  end

  describe 'app.js XSS hygiene + serving (T-13-13)' do
    it 'contains no innerHTML or insertAdjacentHTML — dynamic text is textContent-only' do
      expect(app_js).not_to include('innerHTML')
      expect(app_js).not_to include('insertAdjacentHTML')
    end

    it 'is served from /assets/app.js as JavaScript' do
      res = served('/assets/app.js')
      expect(res.code).to eq('200')
      expect(res['Content-Type']).to eq('application/javascript')
    end

    it 'ships inside the gem (gemspec spec.files membership)' do
      files = Dir.chdir(SPMCache::ROOT) do
        Gem::Specification.load('spm_cache.gemspec').files
      end
      expect(files).to include('lib/spm_cache/web/assets/app.js')
    end
  end

  describe 'app.js source contract — doctor panel (app-shell port: check-list + doctor-summary)' do
    it 'pins the marker vocabulary reused verbatim from doctor.rb' do
      expect(app_js).to include("ok: '✓', warn: '!', fail: '✗'")
    end

    it 'writes check rows into #check-list and tallies into #doctor-summary — never a full-body renderEmpty (would orphan them)' do
      expect(app_js).to include("byId('check-list')")
      expect(app_js).to include("byId('doctor-summary')")
      render_doctor = app_js[/const renderDoctor = \(envelope\) => \{[\s\S]*?\n  \};/]
      expect(render_doctor).not_to include('renderEmpty(')
    end

    it 'the cold-load .loading placeholder is patched/removed in place (never full-body replaceChildren) — check-list/doctor-summary survive every transition' do
      render_doctor = app_js[/const renderDoctor = \(envelope\) => \{[\s\S]*?\n  \};/]
      expect(render_doctor).to include("body.querySelector('.loading')")
      expect(render_doctor).to include('body.dataset.rendered = ')
      expect(render_doctor).to include('loading.textContent =')
      expect(render_doctor).to include('loading.remove();')
    end

    it 'empty state copy verbatim (has_run: false)' do
      expect(app_js).to include('Doctor has not run yet. Select Run Doctor to check your environment.')
    end

    it 'cached stamp derives from the envelope generated_at (em dash, HH:MM:SS)' do
      expect(app_js).to match(/Cached — generated at \$\{fmtHMS\([^)]*\)\}/)
    end

    it 'tallies render as three glyph+count+word spans from the real envelope.data.summary — never re-derived from the checks array' do
      render_doctor = app_js[/const renderDoctor = \(envelope\) => \{[\s\S]*?\n  \};/]
      expect(render_doctor).to include("['fail', '✗', summary.failures, 'failed']")
      expect(render_doctor).to include("['warn', '!', summary.warnings, 'warnings']")
      expect(render_doctor).to include("['ok', '✓', summary.ok, 'passed']")
      expect(render_doctor).to include("class: \`tally tally-${key}\`")
      expect(render_doctor).to include('data.checks.length')
    end

    it 'Run Doctor swaps the label to Running… and back, firing ?run=1' do
      expect(app_js).to include("'/api/doctor?run=1'")
      expect(app_js).to include("'/api/doctor'")
      expect(app_js).to include("'Running…'")
      expect(app_js).to include("'Run Doctor'")
    end

    it 'fix hints render as a labelled command block: "fix" label span + accent .cmd span with the raw hint text' do
      render_doctor = app_js[/const renderDoctor = \(envelope\) => \{[\s\S]*?\n  \};/]
      expect(render_doctor).to include("class: 'fix-hint-label', text: 'fix'")
      expect(render_doctor).to include("class: 'cmd', text: check.fix_hint")
      expect(render_doctor).to include("check.status !== 'ok' && check.fix_hint")
    end

    it '#rail-badge-doctor shows a glyph derived from real summary.failures/warnings — hidden when both are zero' do
      badge = app_js[/const updateDoctorBadge = \(summary\) => \{[\s\S]*?\n  \};/]
      expect(badge).to include('!summary.failures && !summary.warnings')
      expect(badge).to include("failing ? '✗' : '!'")
      expect(badge).to include('rail-status-fail')
      expect(badge).to include('rail-status-warn')
    end

    it 'doctor is on-demand only — the ONLY timer in the file is the state poll' do
      expect(app_js.scan(/window\.setTimeout/).size).to eq(1)
    end

    it 'doctor fetch failures render the panel-name error copy' do
      expect(app_js).to include("'Doctor', err.message")
    end
  end

  describe 'app.js source contract — graph panel (DASH-03, unchanged by this port except the hidden-toggle)' do
    it 'empty state copy verbatim, naming the generating command' do
      expect(app_js).to include("'No dependency graph yet'")
      expect(app_js).to include("'spm-cache use'")
      expect(app_js).to include("' to generate graph.json, then Refresh.'")
    end

    it 'no longer unhides #graph-wrap on success — it starts visible per the ported markup (decision 6)' do
      render_graph = app_js[/const renderGraph = \(envelope\) => \{[\s\S]*?\n  \};/]
      expect(render_graph).not_to match(/byId\('graph-wrap'\)\.hidden = false/)
    end

    it 'stamp format: Updated {MMM d, HH:MM} · generated by spm-cache use (from graph_generated_at)' do
      expect(app_js).to match(/Updated \$\{fmtGraphStamp\([^)]*\)\} · generated by spm-cache use/)
      expect(app_js).to include("'Jan', 'Feb'")
      expect(app_js).to include('d.getDate()')
    end

    it 'renders via the vendored cytoscape with elements AS-SERVED and grid layout' do
      expect(app_js).to include('window.cytoscape(')
      expect(app_js).to include('elements: data.nodes')
      expect(app_js).to include("name: 'grid'")
      expect(app_js).to include("label: 'data(module)'")
    end

    it 'keeps ONE cytoscape instance: destroys the previous graph before re-creating (review IN-01)' do
      expect(app_js).to include('if (cyGraph) cyGraph.destroy();')
      expect(app_js).to include('let cyGraph = null')
      expect(app_js.scan(/window\.cytoscape\(/).size).to eq(1)
    end

    it 'macro nodes are diamonds in the macro color (cachemap precedent)' do
      expect(app_js).to include('[hasMacro="true"]')
      expect(app_js).to include("'diamond'")
    end

    it 'node colors follow the locked status palette' do
      %w[#4CAF50 #FF9800 #9E9E9E #607D8B #3F51B5 #9C27B0].each do |hex|
        expect(app_js).to include(hex)
      end
    end

    it 'zero nodes still render (guarded empty line; legend regardless of count)' do
      expect(app_js).to include('data.nodes.length === 0')
      expect(app_js).to include("'legend-item'")
      expect(app_js).to include("'legend-swatch'")
    end

    it 'nodes are NOT clickable — no event handlers registered (Phase 16 scope)' do
      expect(app_js).not_to match(/\.on\(\s*['"]/)
    end

    it 'graph fetch failures render the panel-name error copy' do
      expect(app_js).to include("'Dependency Graph', err.message")
    end
  end

  describe 'app.js source contract — nav-rail surface switching (app-shell port)' do
    it 'showSurface toggles exactly one .surface visible and its rail-item is-active/aria-current, persisting to localStorage' do
      show_surface = app_js[/const showSurface = \(name\) => \{[\s\S]*?\n  \};/]
      expect(show_surface).to include("classList.toggle('is-active', on)")
      expect(show_surface).to include("setAttribute('aria-current', 'page')")
      expect(show_surface).to include('s.hidden = !on;')
      expect(show_surface).to include('localStorage.setItem(SURFACE_KEY, name)')
    end

    it 'digit keys 1-4 switch surfaces, / focuses the cache filter, Escape blurs — all ignored while typing or a modifier is held' do
      keydown = app_js[/document\.addEventListener\('keydown', \(ev\) => \{[\s\S]*?\n  \}\);/]
      expect(keydown).to include("tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT'")
      expect(keydown).to include('ev.metaKey || ev.ctrlKey || ev.altKey')
      expect(keydown).to include("ev.key >= '1' && ev.key <= '4'")
      expect(keydown).to include("ev.key === '/'")
      expect(keydown).to include("byId('state-filter').focus()")
      expect(keydown).to include("ev.key === 'Escape'")
    end

    it 'boot() restores the persisted surface from localStorage, defaulting to run' do
      boot = app_js[/const boot = \(\) => \{[\s\S]*?\n  \};/]
      expect(boot).to include('localStorage.getItem(SURFACE_KEY)')
      expect(boot).to include("SURFACES.indexOf(savedSurface) !== -1 ? savedSurface : 'run'")
    end

    it 'SURFACES enumerates exactly run/cache/doctor/graph in that order (matches the digit-key mapping)' do
      expect(app_js).to include("const SURFACES = ['run', 'cache', 'doctor', 'graph'];")
    end
  end

  describe 'app.js locked budget' do
    it 'stays within the vanilla-JS LOC budget (app-shell port raised the cap: nav-rail switching + cache filter/chips + doctor tallies/badges)' do
      expect(app_js.lines.length).to be >= 300
      expect(app_js.lines.length).to be <= 800
    end
  end

  describe 'vendored cytoscape.min.js (structural pins — never byte-gated)' do
    it 'records the vendored version in a first-line comment with no scheme URL' do
      first_line = cytoscape_js.lines.first
      expect(first_line).to match(/cytoscape.*\d+\.\d+\.\d+/)
      expect(first_line).not_to match(%r{https?://}i)
    end

    it 'is the real minified dist: > 300 KB of JavaScript, not an HTML error page' do
      expect(cytoscape_js.bytesize).to be > 300 * 1024
      expect(cytoscape_js).not_to include('<html')
    end

    it 'is served from /assets/cytoscape.min.js as JavaScript' do
      res = served('/assets/cytoscape.min.js')
      expect(res.code).to eq('200')
      expect(res['Content-Type']).to eq('application/javascript')
      expect(res.body.bytesize).to eq(File.binread(File.join(asset_dir, 'cytoscape.min.js')).bytesize)
    end

    it 'ships inside the gem (gemspec spec.files membership)' do
      files = Dir.chdir(SPMCache::ROOT) do
        Gem::Specification.load('spm_cache.gemspec').files
      end
      expect(files).to include('lib/spm_cache/web/assets/cytoscape.min.js')
      expect(files).to include('lib/spm_cache/web/assets/index.html')
      expect(files).to include('lib/spm_cache/web/assets/styles.css')
    end
  end

  describe 'styles.css design tokens (Grok/xAI monochrome palette — app-shell port)' do
    it 'declares the spacing scale, every value a multiple of 4' do
      tokens = styles_css.scan(/--space-[a-z0-9]+:\s*(\d+)px/).flatten.map(&:to_i)
      expect(tokens).to contain_exactly(4, 8, 16, 24, 32)
      tokens.each { |px| expect(px % 4).to eq(0) }
    end

    it 'declares every locked color token verbatim (the Grok monochrome pass)' do
      {
        '--c-bg' => '#000000', '--c-panel' => '#171717', '--c-border' => '#2E2E2E',
        '--c-accent' => '#FFFFFF', '--c-fail' => '#F44336', '--c-text' => '#F2F2F2',
        '--c-muted' => '#8E8E93', '--c-ok' => '#4CAF50', '--c-warn' => '#FF9800',
        '--c-neutral' => '#9E9E9E', '--c-excluded' => '#7A7A7E',
        '--c-plugin' => '#3F51B5', '--c-macro' => '#9C27B0',
        '--c-canvas' => '#000000', '--c-elevated' => '#313131',
        '--c-border-muted' => '#1C1C1C', '--c-fg-gutter' => '#6B6B70', '--c-line' => '#545458'
      }.each { |token, value| expect(styles_css).to include("#{token}: #{value}") }
    end

    it 'never reintroduces the old GitHub-dark blue accent (#2196F3) anywhere' do
      expect(styles_css).not_to include('#2196F3')
    end

    it 'declares both font stacks: system + ui-monospace, with tabular-nums for mono data' do
      expect(styles_css).to include('--font-system: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif')
      expect(styles_css).to include('--font-mono: ui-monospace, SFMono-Regular, Menlo, monospace')
      expect(styles_css).to include('font-variant-numeric: tabular-nums')
    end

    it 'weights are 400/500/600/700 only; the ONE italic rule is the elision notice, never body/data text' do
      %w[400 500 600 700].each { |w| expect(styles_css).to include("font-weight: #{w}") }
      expect(styles_css.scan(/font-style: italic/).size).to eq(1)
      expect(styles_css).to include('.log-elision { color: var(--c-muted); font-style: italic; }')
    end

    it 'app shell: 100dvh grid, a 52px topbar row, a fixed-width nav rail' do
      expect(styles_css).to include('--topbar-h: 52px')
      expect(styles_css).to include('height: 100dvh')
      expect(styles_css).to include('grid-template-rows: var(--topbar-h) auto minmax(0, 1fr)')
      expect(styles_css).to include('--rail-w: 208px')
    end

    it 'the log viewport is elastic (flex: 1 1 auto; min-height: 0), not the old fixed 480px well — this is the redesign\'s core fix' do
      expect(styles_css).not_to match(/height: 480px/)
      log_viewport = styles_css[/\.log-viewport\s*\{[^}]*\}/]
      expect(log_viewport).to include('flex: 1 1 auto')
      expect(log_viewport).to include('min-height: 0')
    end

    it 'buttons: .btn-primary/.btn-danger/.log-pill-btn keep the AA dark-foreground-on-accent-fill pattern (W1), now at ≈21:1 with white' do
      %w[.btn-primary .btn-danger .log-pill-btn].each do |sel|
        block = styles_css[/#{Regexp.escape(sel)}\s*\{[^}]*\}/]
        expect(block).to include('color: var(--c-bg)')
      end
      expect(styles_css).not_to include('color: #FFFFFF')
      expect(styles_css).not_to include('color: #fff')
    end

    it 'exactly one solid accent BUTTON in the whole shell: #ctl-build (.btn-primary) — every other control is quiet/danger/warn' do
      expect(index_html).to match(/class="btn btn-primary" id="ctl-build"/)
      expect(index_html).not_to match(/class="btn btn-primary"[^>]*id="(?!ctl-build)/)
    end

    it 'badges: colored text on a wash-tinted fill' do
      %w[badge-ok badge-warn badge-fail badge-neutral badge-excluded badge-plugin].each do |cls|
        expect(styles_css).to include(".#{cls}")
      end
    end

    it 'the state table is fixed-layout with the six pinned column widths summing to 100' do
      widths = { '.col-name' => 30, '.col-config' => 11, '.col-size' => 10,
                 '.col-state' => 13, '.col-fidelity' => 22, '.col-cached' => 14 }
      widths.each { |sel, pct| expect(styles_css).to include("#{sel} { width: #{pct}%; }") }
      expect(widths.values.sum).to eq(100)
    end

    it 'mono for sizes/fidelity/stamps/port label; fix hints render as a canvas-backed command block' do
      expect(styles_css).to include('font-family: var(--font-mono)')
      expect(styles_css).to include('.mono {')
      expect(styles_css).to include('.fix-hint {')
      expect(styles_css).to include('background: var(--c-canvas)')
    end

    it 'accent text appears on cmd command references and the log-live liveness class (connected pill + running status) — one shared declaration' do
      expect(styles_css).to match(/\.cmd,\s*\.log-live\s*\{/)
    end

    it 'the connecting pill defaults to muted (neutral) — only .log-live (connected) and .conn-pill-reconnecting override it' do
      conn_pill = styles_css[/\.conn-pill\s*\{[^}]*\}/]
      expect(conn_pill).to include('color: var(--c-muted)')
    end
  end

  describe 'checkbox + toggle column styling (Phase 16 — ported values)' do
    it 'the checkbox: accent checked-state colour, disabled opacity, and a focus ring — exactly one accent-color declaration' do
      expect(styles_css).to include('.state-table input[type="checkbox"] {')
      expect(styles_css).to include('accent-color: var(--c-accent);')
      expect(styles_css).to include('.state-table input[type="checkbox"]:disabled { opacity: 0.45; cursor: default; }')
      expect(styles_css).to include('.state-table input[type="checkbox"]:focus-visible')
      expect(styles_css.scan(/accent-color:/).size).to eq(1)
    end
  end

  # Plan 14-04 — the Run Log panel and its second ES module, pinned
  # the same way: SERVED bytes for the route rows, FILE bytes for
  # every copy string and mechanic. The 14-UI-SPEC Prohibitions
  # section is testable here: no markup-writing APIs, no client
  # clock, no scheme-absolute refs, no color-only status.
  describe 'log.js + Run Log panel (Plan 14-04, app-shell port)' do
    let(:log_js) { File.read(File.join(asset_dir, 'log.js')) }

    describe 'serving + module registration' do
      it 'serves /assets/log.js as JavaScript, referenced RELATIVE after app.js, and ships in the gem' do
        res = served('/assets/log.js')
        expect(res.code).to eq('200')
        expect(res['Content-Type']).to eq('application/javascript')
        expect(index_html).to include('<script type="module" src="assets/log.js"></script>')
        expect(index_html.index('assets/app.js')).to be < index_html.index('assets/log.js')
        files = Dir.chdir(SPMCache::ROOT) do
          Gem::Specification.load('spm_cache.gemspec').files
        end
        expect(files).to include('lib/spm_cache/web/assets/log.js')
      end
    end

    describe 'stream wiring (14-01 contract)' do
      it 'reads the shared sessionStorage token key and connects EventSource on the query param' do
        expect(log_js).to include("'spm-cache-web-token'")
        expect(log_js).to include("'/api/events?token=' + token")
      end

      it 'registers named listeners for hello/entry/switch/notice — the module ships whole' do
        %w[hello entry switch notice].each do |name|
          expect(log_js).to include("addEventListener('#{name}'")
        end
      end
    end

    describe 'connection states' do
      it 'pins the three pill states; CLOSED replaces the whole .app shell with the locked token-invalid page' do
        expect(log_js).to include("'● connecting…'")
        expect(log_js).to include("'● connected'")
        expect(log_js).to include("'↻ reconnecting…'")
        expect(log_js).to include('readyState === EventSource.CLOSED')
        expect(log_js)
          .to include("This page's access token is no longer valid. Restart spm-cache web and open the URL it prints.")
        expect(log_js).to include("querySelector('.app')")
      end
    end

    describe 'cold load (D-13)' do
      it 'live run: ● running card, replay renders with follow off until completion' do
        expect(log_js).to include("running: { glyph: '●', word: 'running', cls: 'log-live' }")
        expect(log_js).to include('follow = false')
        expect(log_js).to include('replaying = true')
      end

      it 'finished run: end-state card + the Started/completed time row' do
        expect(log_js).to include('Started ${fmtStamp(')
        expect(log_js).to include('` · completed ${relative(endIso)}`')
        expect(log_js).to include("word: 'success'")
        expect(log_js).to include("word: 'failed'")
      end

      it 'empty runs dir: pinned empty state in the accent .cmd span; only the pill lives' do
        expect(log_js).to include("'No runs yet'")
        expect(log_js).to include("'spm-cache build'")
        expect(log_js).to include("' to produce the first run log.'")
        expect(log_js).to include("class: 'cmd'")
        expect(log_js).to include("=== 'idle'")
      end

      it 'muted Loading… before the first stream byte; no card unhide until hello' do
        expect(log_js).to include("'Loading…'")
        expect(log_js).to include("class: 'loading'")
        expect(log_js).to include('card.hidden = false')
      end
    end

    describe 'line rendering (T-12-01)' do
      it 'out lines verbatim via textContent; err lines carry the ✗ prefix in :fail' do
        expect(log_js).to include("data.stream === 'err'")
        expect(log_js).to include('COPY.errPrefix + text')
        expect(log_js).to include("errPrefix: '✗ '")
        expect(log_js).to include("replace(/\\n$/, '')")
        expect(log_js).to include('log-line log-err')
      end

      it 'dividers ── name ── for package_start/phase; no line for run_start/run_end/package_end/sh; unknown keys ignored' do
        expect(log_js).to include('divider: (name) => `── ${name} ──`')
        expect(log_js).to include("data.event === 'package_start' || data.event === 'phase'")
        expect(log_js).to include("data.event === 'package_end' || data.event === 'sh'")
        expect(log_js).to include('data.event !== undefined')
        expect(log_js).to include("data.event === 'run_start'")
      end

      it '#log-count mirrors ringCount + evicted on every append/eviction and every run reset' do
        expect(log_js).to include('const updateLogCount = () => {')
        expect(log_js).to include('`${ringCount + evicted} lines`')
        append = log_js[/const appendLine = \(node\) => \{[\s\S]*?\n  \};/]
        expect(append).to include('updateLogCount();')
        expect(log_js.scan(/updateLogCount\(\);/).size).to be >= 3 # appendLine + resetForRun + renderEmptyState
      end
    end

    describe 'identity card (D-06/D-11) + topbar mirror (app-shell port)' do
      it 'rows: status · trigger badge · mono-600 command · Config · Started(+completed) · argv + run id with titles · redacted suffix' do
        expect(log_js).to include('Config ${')
        expect(log_js).to include("'—'")
        expect(log_js).to include("spm-cache ${parts.join(' ')}")
        expect(log_js).to include(' · credentials redacted')
        expect(log_js).to include('.title = ')
      end

      it 'trigger renders verbatim — a class map only, never a value allowlist' do
        expect(log_js).to include("watch: 'plugin'")
        expect(log_js).to include("TRIGGER_CLASS[currentHeader.trigger] || 'neutral'")
        expect(log_js).not_to include("['terminal'")
      end

      it 'card status vocabulary: glyph+word pairs exactly per the UI-SPEC table (CP14 phrase included)' do
        expect(log_js).to include("word: 'running'")
        expect(log_js).to include("word: 'success'")
        expect(log_js).to include("word: 'failed'")
        expect(log_js).to include("word: 'interrupted — exit unknown'")
      end

      it 'statusKey maps the FULL CP14 phrase to interrupted — the server vocabulary, never running (D-14 probe catch)' do
        expect(log_js).to include("if (status === 'interrupted' || status === 'interrupted — exit unknown') return 'interrupted';")
      end

      it 'the SAME derived status/glyph additionally mirrors into #topbar-state — visible on every surface, no new data source' do
        set_status = log_js[/const setCardStatus = \(key\) => \{[\s\S]*?\n  \};/]
        expect(set_status).to include('topbarStateEl.textContent = `${status.glyph} ${status.word}`;')
        expect(log_js).to include("const TOPBAR_STATE_SUFFIX = { running: 'run', success: 'ok', failed: 'fail', interrupted: 'warn' };")
      end

      it 'the SAME command mirrors into #runstat-cmd — no client clock, no new fetch, same currentHeader.command source' do
        build_card = log_js[/const buildCard = \(header, key\) => \{[\s\S]*?\n  \};/]
        expect(build_card).to include('runstatCmdEl.textContent = currentHeader.command')
      end
    end

    describe 'prohibitions (14-UI-SPEC)' do
      it 'zero markup-writing APIs — every dynamic string flows through el()/textContent (T-14-16)' do
        %w[innerHTML insertAdjacentHTML document.write outerHTML].each do |api|
          expect(log_js).not_to include(api)
        end
        expect(log_js).to include('node.textContent = opts.text')
      end

      it 'no client clock — relative times derive from the hello now stamp + event ts (T-14-17)' do
        expect(log_js).not_to include('Date.now')
        expect(log_js).to include('new Date(payload.now)')
        expect(log_js).to include('new Date(iso)')
      end

      it 'offline: zero scheme-absolute URLs, zero cdn. references' do
        expect(log_js).not_to match(%r{https?://}i)
        expect(log_js).not_to match(/cdn\./i)
      end

      it "independence: no timers of any kind in log.js — the state poll stays app.js's only timer" do
        expect(log_js).not_to include('setTimeout')
        expect(log_js).not_to include('setInterval')
        expect(log_js).not_to include('requestAnimationFrame')
        expect(log_js.scan(/new EventSource\(/).size).to eq(1)
      end

      it 'glyph inventory: ● and ↻ added; the verdict triple ✓/!/✗ reused' do
        %w[● ↻ ✓ ✗].each { |glyph| expect(log_js).to include(glyph) }
        expect(log_js).to include("glyph: '!'")
      end
    end

    describe 'index.html + styles.css skeleton' do
      it 'Run Log surface FIRST with the a11y-complete skeleton' do
        expect(index_html.index('id="surface-run"')).to be < index_html.index('id="surface-cache"')
        expect(index_html).to include('<div class="log-viewport" id="log-viewport" role="log" aria-live="off" aria-label="Run output" tabindex="0"></div>')
        expect(index_html).to include('>Phases</div>')
        expect(index_html).to include('>Packages</div>')
        expect(index_html).to include('id="log-overlay"')
        expect(index_html).to include('id="log-banner" role="alert"')
      end

      it 'styles: the log stream well is a true-black canvas with pre-wrap mono lines, elastic (not fixed) height' do
        expect(styles_css).to include('.log-viewport')
        expect(styles_css).to include('white-space: pre-wrap')
        log_stream_col = styles_css[/\.log-stream-col\s*\{[^}]*\}/]
        expect(log_stream_col).to include('background: var(--c-canvas)')
      end
    end

    describe 'follow/pause + banners + a11y (app-shell port: static persistent nodes, not created-per-call)' do
      it 'follow pins instantly: scrollTop = scrollHeight on append, no smooth behavior, ANY upward scroll disengages' do
        expect(log_js).to include('viewport.scrollTop = viewport.scrollHeight')
        expect(log_js).not_to include('smooth')
        expect(log_js).not_to include('scrollIntoView')
        expect(log_js).to include('viewport.scrollTop < lastScrollTop')
      end

      it 'the pause pill is the static #log-follow-btn node, patched (hidden + label) — never created/appended per call' do
        pill_fn = log_js[/const renderPill = \(\) => \{[\s\S]*?\n  \};/]
        expect(pill_fn).not_to match(/if \(!pauseBtn\)/)
        expect(pill_fn).not_to include('overlay.append')
        expect(pill_fn).to include('pauseBtn.hidden = false;')
        expect(pill_fn).to include('pauseBtn.hidden = true;')
        expect(pill_fn).to include('pauseBtn.textContent = COPY.paused(pending);')
        expect(log_js).to include("const pauseBtn = byId('log-follow-btn');")
        expect(log_js).to include('paused: (n) => `paused — ${n} new lines · jump to live`')
      end

      it "the pause pill's click listener attaches ONCE at boot(), not per render" do
        boot = log_js[/const boot = \(\) => \{[\s\S]*?\n  \};/]
        expect(boot).to include('pauseBtn.addEventListener(\'click\', resumeFollow);')
      end

      it 'during initial replay the pill never shows; follow engages at completion (D-01/D-13)' do
        expect(log_js).to include('if (replaying && atBottom()) replaying = false;')
        expect(log_js).to include("viewport.addEventListener('scroll'")
        expect(log_js).to include('const atBottom = () =>')
      end

      it 'non-zero run_end → sticky Run failed banner via #log-banner-text, role=alert, NO dismiss control' do
        expect(log_js).to include('failedBanner: (status) => `Run failed — exit status ${status}`')
        expect(log_js).to include("jumpToError: 'Jump to first error'")
        expect(log_js).to include('bannerTextEl.textContent =')
        expect(log_js).to include('bannerEl.hidden = false;')
        expect(log_js).not_to match(/dismiss/i)
        expect(log_js).not_to include("'Close'")
        expect(index_html).to include('id="log-banner-jump">Jump to first error</button>')
      end

      it 'the banner glyph/class flip dynamically between fail (✗) and warn (!) on the static glyph span' do
        show_banner = log_js[/const showBanner = \(kind, status\) => \{[\s\S]*?\n  \};/]
        expect(show_banner).to include("querySelector('.log-banner-glyph')")
        expect(show_banner).to include("failed ? '✗' : '!'")
      end

      it "the banner jump button's click listener attaches ONCE at boot(), not per showBanner call" do
        boot = log_js[/const boot = \(\) => \{[\s\S]*?\n  \};/]
        expect(boot).to include('bannerJumpBtn.addEventListener(\'click\', jumpToFirstError);')
        show_banner = log_js[/const showBanner = \(kind, status\) => \{[\s\S]*?\n  \};/]
        expect(show_banner).not_to include('addEventListener')
      end

      it 'CP14 interrupt → Run interrupted — exit unknown. banner with the same jump button' do
        expect(log_js).to include("interruptedBanner: 'Run interrupted — exit unknown.'")
        expect(log_js).to include("showBanner('interrupted')")
      end

      it 'the aria-live status container flips on the corresponding event (card flip)' do
        expect(log_js).to include('const onRunEnd = (data) => {')
        expect(log_js).to include("setCardStatus('failed')")
        expect(log_js).to include("setCardStatus('success')")
      end

      it 'jump chain: first err line → final line → oldest retained under ring eviction; never a silent no-op (D-02/D-03)' do
        expect(log_js).to include('const RING_LIMIT = 500;')
        expect(log_js).to include('elision: (n) =>')
        expect(log_js).to include('let firstErrEl = null;')
        expect(log_js).to include('let errEvicted = false;')
        expect(log_js).to include("querySelectorAll('.log-line.log-err')")
        expect(log_js).to include('const jumpTarget = () => {')
        expect(log_js).to include('const clearFilter = () => {')
      end

      it 'the banner belongs to the displayed run — switching re-derives the slot, never a user dismiss' do
        expect(log_js.scan(/hideBanner\(\)/).size).to be >= 2
        expect(log_js).to match(/resetForRun = \(name, followOn\) => \{[\s\S]*?hideBanner\(\);/)
        expect(log_js).to match(/resetForRun\(data\.run, true\)/)
      end

      it 'focus-visible accent rings cover pill/chip/select/filter-pill controls; native button only; pill name = full label' do
        %w[.log-pill-btn .log-chip .log-runs-select .log-filter-pill].each do |rule|
          expect(styles_css).to include("#{rule}:focus-visible")
        end
        expect(styles_css).to include('outline: 2px solid var(--c-accent)')
      end

      it 'teardown safety: the token-invalid replacement stops every stream handler (app.js bail-out guard)' do
        expect(log_js).to include('let dead = false;')
        expect(log_js.scan(/if \(!alive\(\)\) return;/).size).to be >= 4
        expect(log_js).to include("byId('log-viewport')")
      end
    end
  end

  # Plan 14-05 Task 1 — the anchor rail (D-07/D-08), jump + filter
  # dimming (D-09), the filter pill, and banner piercing (D-10).
  # Unaffected by the app-shell port except the filter pill's DOM
  # lifecycle (created-per-call → static-patched) and its active
  # styling (the redesign's own accent-badge choice for the chip).
  describe 'log.js anchor rail + filter + piercing (Plan 14-05)' do
    let(:log_js) { File.read(File.join(asset_dir, 'log.js')) }

    it 'chips: package names verbatim + the four phase markers; duplicates dedupe by name, first position wins (A10); no chips for no-line or unknown events' do
      expect(log_js).to include("addAnchor('package', name, divider)")
      expect(log_js).to include("addAnchor('phase', name, divider)")
      expect(log_js).to include('if (anchors.some((a) => a.kind === kind && a.name === name)) return;')
      expect(log_js.scan(/addAnchor\(/).size).to eq(2)
      expect(log_js).to match(/data\.event === 'package_start' \|\| data\.event === 'phase'[\s\S]*?addAnchor\('package'/)
    end

    it 'rail DOM: Phases precedes Packages (labels always rendered); chips stack with ellipsized labels + title tooltips' do
      expect(index_html.index('>Phases</div>')).to be < index_html.index('>Packages</div>')
      expect(log_js).to include("const railPhases = byId('rail-phases');")
      expect(log_js).to include("const railPackages = byId('rail-packages');")
      expect(styles_css).to include('.log-chip {')
      expect(styles_css).to match(/\.log-chip\s*\{[^}]*text-overflow: ellipsis/)
      expect(log_js).to include('text: anchor.name, title: anchor.name')
    end

    it 'jump: chip activation scrolls to the anchor divider element via the registry and disengages follow (D-09 + the 14-04 seam)' do
      expect(log_js).to include('const jumpToAnchor = (anchor) => {')
      expect(log_js).to include('anchor.lineEl && anchor.lineEl.isConnected')
      expect(log_js).to match(/const jumpToAnchor = \(anchor\) => \{[\s\S]*?follow = false;/)
      expect(log_js).to include('jumpToAnchor(anchor);')
    end

    it 'package filter: the package_start..package_end segment stays primary (inclusive); every other line takes the dim class; NO line leaves the DOM (A5)' do
      expect(log_js).to include('const matches = (line) => {')
      expect(log_js).to include('seg.pkg === activeFilter.name')
      expect(log_js).to include("classList.toggle('log-dim', !matches(node));")
      apply = log_js[/const applyFilter = \(\) => \{[\s\S]*?\n  \};/]
      expect(apply).to include("classList.toggle('log-dim', !matches(line));")
      expect(apply).not_to include('remove')
    end

    it 'phase filter: from the marker to the line before the next phase marker OR package_start (segment rules verbatim)' do
      expect(log_js).to include('seg.phase === activeFilter.name')
      expect(log_js).to include('segPackage = name;')
      expect(log_js).to include('segPhase = null;')
      expect(log_js).to include('SEG.set(divider, { pkg: name, phase: null });')
      expect(log_js).to include('SEG.set(divider, { pkg: null, phase: name });')
    end

    it 'filter pill: the static #log-filter-pill node is patched (label/title/hidden) — never created per call; activation clears the filter with the view put' do
      expect(log_js).to include('filtered: (name) => `filtered: ${name}`')
      pill_fn = log_js[/const renderPill = \(\) => \{[\s\S]*?\n  \};/]
      expect(pill_fn).not_to match(/if \(!filterBtn\)/)
      expect(pill_fn).to include('filterBtn.textContent = COPY.filtered(activeFilter.name);')
      expect(pill_fn).to include('filterBtn.title = COPY.filtered(activeFilter.name);')
      boot = log_js[/const boot = \(\) => \{[\s\S]*?\n  \};/]
      expect(boot).to include('filterBtn.addEventListener(\'click\', clearFilter);')
      expect(styles_css).to match(/\.log-filter-pill\s*\{[^}]*max-width: 240px[^}]*text-overflow: ellipsis/)
      expect(index_html).to match(%r{id="log-filter-pill" hidden></button>})
    end

    it 'active chip: aria-pressed=true + the redesign\'s own accent-wash badge style; clicking the ACTIVE chip clears the filter with the view staying put' do
      expect(log_js).to include("chip.setAttribute('aria-pressed', isActive ? 'true' : 'false');")
      expect(log_js).to match(%r{if \(isActive\) \{\s*clearFilter\(\); //})
      expect(styles_css).to include('.log-chip-active')
      log_chip_active = styles_css[/\.log-chip-active\s*\{[^}]*\}/]
      expect(log_chip_active).to include('background: var(--wash-accent)')
    end

    it 'piercing: the banner renders regardless of filter state — its slot sits outside the filtered viewport and its render path never reads filter state (D-10)' do
      expect(index_html.index('id="log-banner"')).to be < index_html.index('id="log-viewport"')
      on_run_end = log_js[/const onRunEnd = \(data\) => \{[\s\S]*?\n  \};/]
      expect(on_run_end).to include("showBanner('failed', status)")
      expect(on_run_end).not_to include('activeFilter')
      show_banner = log_js[/const showBanner = \(kind, status\) => \{[\s\S]*?\n  \};/]
      expect(show_banner).not_to include('activeFilter')
      expect(log_js).to include("viewport.querySelectorAll('.log-line').forEach((line) => {")
    end

    it 'exit-filter jump: Jump to first error clears the filter FIRST (pill removed, dim removed, chips revert) and THEN moves the view (D-10)' do
      expect(log_js).to match(/const jumpToFirstError = \(\) => \{[\s\S]*?clearFilter\(\);[\s\S]*?viewport\.scrollTop/)
      expect(log_js).to include("viewport.querySelectorAll('.log-line.log-dim')")
    end

    it 'eviction interplay: an anchor jump whose target left the ring lands on the oldest retained line — never a no-op (D-02 degradation)' do
      target = log_js[/const anchorTarget = \(anchor\) => \{[\s\S]*?\n  \};/]
      expect(target).to include('anchor.lineEl.isConnected')
      expect(target).to include('lines.length > 0 ? lines[0] : null')
    end
  end

  # Plan 14-05 Task 2 — auto-switch + switch notice (D-04), the
  # recent-runs dropdown (D-12), and verbatim notice/lock-wait
  # rendering (D-05). Unaffected by the app-shell port except the
  # switch notice's DOM lifecycle (created-per-call → static-patched).
  describe 'log.js auto-switch + recent runs + notices (Plan 14-05)' do
    let(:log_js) { File.read(File.join(asset_dir, 'log.js')) }

    it 'auto-switch: UNCONDITIONAL reset (fresh replay, follow on, filter cleared, banner re-derived); a pinned connection drops the pin, closes the stream, reconnects via the plain URL' do
      expect(log_js).to match(/resetForRun\(data\.run, true\)/)
      expect(log_js).to include('const previousRun = currentRun;')
      expect(log_js).to include('if (pinned) {')
      expect(log_js).to include('pinned = false;')
      expect(log_js).to include('source.close();')
      expect(log_js).to include('connect(storedToken());')
      expect(log_js).not_to include('data.run === currentRun')
    end

    it "switch notice: the static #log-switch-btn is patched with the PREVIOUSLY-DISPLAYED run's id (view state, never the wire's previous field)" do
      expect(log_js).to include("switchNotice: 'switched to new run — previous: '")
      expect(index_html).to include('switched to new run — previous: ')
      expect(log_js).to include('let switchTargetRun = null;')
      render_notice = log_js[/const renderSwitchNotice = \(previousRun\) => \{[\s\S]*?\n  \};/]
      expect(render_notice).to include('switchTargetRun = previousRun;')
      expect(render_notice).to include('switchBtn.textContent = previousRun;')
      expect(render_notice).to include('switchBtn.title = previousRun;')
      expect(render_notice).not_to include('el(\'button\'')
      expect(render_notice).not_to include('replaceChildren')
      expect(log_js).not_to include('data.previous')
    end

    it "the switch button's click listener attaches ONCE at boot(), reading switchTargetRun (the old per-call closure no longer exists)" do
      boot = log_js[/const boot = \(\) => \{[\s\S]*?\n  \};/]
      expect(boot).to include('switchBtn.addEventListener(\'click\', () => { if (switchTargetRun) loadRun(switchTargetRun); });')
    end

    it 'no previously-displayed run → NO notice: the slot stays hidden (first run of a session; a switch arriving into the empty state)' do
      expect(log_js).to include('if (!switchBar || !previousRun) return;')
    end

    it 'loadRun: ONE path for the notice control and dropdown selections — close the stream, reconnect with ?run= (encodeURIComponent), no page reload' do
      expect(log_js).to include('const loadRun = (name) => {')
      expect(log_js).to include("'&run=' + encodeURIComponent(run)")
      expect(log_js).to include('connect(storedToken(), name);')
      expect(log_js).to match(/loadRun\(runsSelect\.value\)/)
      expect(log_js.scan(/const loadRun = /).size).to eq(1)
      expect(log_js).not_to include('location.reload')
      expect(log_js).not_to include('window.open')
    end

    it 'dropdown fetch: every OPEN re-fires a token-gated /api/runs fetch (X-SPM-Token, envelope check); the viewing suffix marks the displayed run' do
      expect(log_js).to include("window.fetch('/api/runs', { headers: { 'X-SPM-Token': storedToken() } })")
      expect(log_js).to include("runsSelect.addEventListener('click', refreshRuns);")
      expect(log_js).to include("runsSelect.addEventListener('focus', refreshRuns);")
      expect(log_js).to include("envelope.status === 'error'")
      expect(log_js).to include("viewingSuffix: ' · viewing'")
      expect(log_js).to include('entry.run === currentRun ? COPY.viewingSuffix')
    end

    it "entry template '{glyph} {command} · {relative}' — the glyph per derived state; 10 newest, newest first" do
      expect(log_js).to include('const RUNS_GLYPH = {')
      expect(log_js).to include("running: '●',")
      expect(log_js).to include("success: '✓',")
      expect(log_js).to include("failed: '✗',")
      expect(log_js).to include("'interrupted — exit unknown': '!',")
      expect(log_js).to match(/`\$\{glyph\} \$\{entry\.command\} · \$\{relative\(entry\.started_at\)\}\$\{viewing\}`/)
    end

    it "empty dir: ONE disabled 'No runs yet' entry" do
      expect(log_js).to include("el('option', { text: COPY.noRunsTitle, disabled: true })")
      expect(log_js).to include('if (opts.disabled) node.disabled = true;')
    end

    it "fetch pending: a single 'Loading…' entry renders while the open's fetch is in flight" do
      expect(log_js).to include("runsSelect.replaceChildren(el('option', { text: COPY.loading, disabled: true }));")
      expect(log_js).to include('let runsFetching = false;')
    end

    it "fetch failure: 'Couldn't load the run list: {message}. Reload the page to retry.' renders in the panel; the last good list stays" do
      expect(log_js).to include("runsError: (message) => `Couldn't load the run list: ${message}. Reload the page to retry.`")
      expect(log_js).to include('const renderRunsError = (message) => {')
      expect(log_js).to include("body.querySelector('.panel-error')?.remove();")
      expect(log_js).to include('let lastRuns = null;')
    end

    it 'fresh derivation: no caching of the runs response across opens — the only guard is the in-flight dedupe; no TTL, no memo skip (CP10 client-side)' do
      expect(log_js).to include('if (!alive() || runsFetching) return;')
      expect(log_js).not_to include('runsCache')
    end

    it "in-stream notices render '! {message}' in warn byte-identically — the two known server strings are server-authored (events.rb pins them), never client copies" do
      expect(log_js).to include('notice: (message) => `! ${message}`')
      expect(log_js).to include("class: 'log-line log-notice'")
      expect(log_js).not_to include('lines dropped')
      expect(log_js).not_to include('run log pruned')
      expect(log_js).to include('if (pinned) {')
      events_rb = File.read(File.join(SPMCache::ROOT, 'lib/spm_cache/web/events.rb'))
      expect(events_rb).to include('lines dropped')
      expect(events_rb).to include('run log pruned while viewing; switching to newest')
    end

    it "lock-wait: 'Waiting for build lock…' renders as a plain out line — no badge, no card lock state, no special-case RENDER path (A11)" do
      expect(log_js.scan(/Waiting for build lock…/).size).to eq(1)
      expect(log_js).not_to include('.lock')
      expect(log_js).not_to include('lock-wait')
      expect(log_js).not_to include('payload.lock')
      expect(log_js).to include("class: isErr ? 'log-line log-err' : 'log-line',")
      append = log_js[/const appendBody = \(data\) => \{[\s\S]*?\n  \};/]
      expect(append).not_to include('Waiting for build lock')
      expect(log_js).to include('} else if (cardPending) {')
    end
  end

  # Plan 15-05 — the controls surface. Now living in the topbar per the
  # app-shell redesign (rationale section 2: "build controls moved out
  # of the Run panel"). The copy table stays byte-exact; the row
  # renders unconditionally (A5); the busy answer stays branchable from
  # a failure at the call site.
  describe 'build controls (Plan 15-05 Task 1, app-shell port: topbar not the Run Log panel)' do
    let(:log_js) { File.read(File.join(asset_dir, 'log.js')) }

    it 'structure: three native buttons in pinned DOM order inside #build-controls, in the topbar-right group + the message slot' do
      topbar_right_at = index_html.index('<div class="topbar-right">')
      build_controls_at = index_html.index('<div class="build-controls" id="build-controls">')
      alert_rail_at = index_html.index('<div class="alert-rail" id="alert-rail">')
      expect(build_controls_at).to be > topbar_right_at
      expect(index_html).not_to include('build-controls" hidden') # A5: static markup, never data-gated
      row = index_html[%r{<div class="build-controls"[\s\S]*?</div>}]
      expect(row).to include('id="ctl-build">Build</button>')
      expect(row).to include('id="ctl-rebuild">Rebuild all</button>')
      expect(row).to include('id="ctl-rollback">Rollback</button>')
      expect(row.index('id="ctl-build"')).to be < row.index('id="ctl-rebuild"')
      expect(row.index('id="ctl-rebuild"')).to be < row.index('id="ctl-rollback"')
      expect(row).to include('id="ctl-message" aria-live="polite" hidden')
      # the confirm bar (Task 2) lives in the alert rail, a SIBLING structure — not nested in build-controls
      expect(alert_rail_at).to be < index_html.index('<div class="shell">')
    end

    it 'copy: the three button labels are byte-exact against the 15-UI-SPEC copy table (Rebuild all capitalized)' do
      expect(index_html.scan(%r{<button[^>]*>(Build|Rebuild all|Rollback)</button>}).flatten)
        .to eq(['Build', 'Rebuild all', 'Rollback'])
    end

    it 'accessibility: every control is a native button with an explicit non-submit type; the message slot is polite-live and starts hidden' do
      %w[ctl-build ctl-rebuild ctl-rollback].each do |id|
        expect(index_html).to match(/<button type="button"[^>]*id="#{id}">/)
      end
      expect(index_html.scan(/<button type="button"/).size).to be >= 3
      expect(index_html).to include('id="ctl-message" aria-live="polite" hidden')
    end

    it 'POST helper: launch token in the X-SPM-Token header with a JSON content type, the HTTP status returned beside the parsed envelope — never a throw, never a token in a URL' do
      helper = app_js[/const requestPost = async \(path, body\) => \{[\s\S]*?\n  \};/]
      expect(helper).to include("'X-SPM-Token': token")
      expect(helper).to include("'Content-Type': 'application/json'")
      expect(helper).to include('status: res.status')
      expect(helper).not_to include('throw')
      expect(app_js.scan(/const requestPost = /).size).to eq(1)
      expect(app_js).not_to include('token=')
    end

    it 'auth inheritance: 401/403 on the POST path reuses the shared token-invalid page replacement, never a row message' do
      helper = app_js[/const requestPost = async \(path, body\) => \{[\s\S]*?\n  \};/]
      expect(helper).to include('res.status === 401 || res.status === 403')
      expect(helper).to include('renderTokenInvalid();')
      settle = app_js[/const settle = \(name, ans\) => \{[\s\S]*?\n  \};/]
      expect(settle).to include('if (ans.status === 401 || ans.status === 403) return;')
    end

    it 'bodies: the incremental click sends the build scope and the forced click the rebuild scope, to /api/build exactly as 15-04 shipped it' do
      expect(app_js).to include("requestPost('/api/build', { scope })")
      expect(app_js).to include("clickBuild('build')")
      expect(app_js).to include("clickBuild('rebuild')")
    end

    it 'pending state: a click disables all three controls before the request resolves (the double-submit guard)' do
      click = app_js[/const clickBuild = \(scope\) => \{[\s\S]*?\n  \};/]
      expect(click.index('freeze(true);')).to be < click.index('requestPost(')
      freeze = app_js[/const freeze = \(on\) => \{[\s\S]*?\n  \};/]
      expect(freeze).to include('Object.values(ctl).forEach')
      expect(freeze).to include('b.disabled = on')
    end

    it 'in-flight state: a 2xx sets the verb pinned message and keeps the controls disabled' do
      settle = app_js[/const settle = \(name, ans\) => \{[\s\S]*?\n  \};/]
      expect(settle).to include('freeze(true);')
      expect(settle).to include('say(CTRL.inflight[name])')
      expect(app_js).to include("build: 'Building…', rebuild: 'Rebuilding all…', rollback: 'Restoring source mode…',")
    end

    it 'busy state: a 409 branches BEFORE the failure arm, renders the pinned busy sentence and re-enables; the server reason value appears nowhere in the assets' do
      settle = app_js[/const settle = \(name, ans\) => \{[\s\S]*?\n  \};/]
      expect(settle.index('ans.status === 409')).to be < settle.index('!ans.ok')
      expect(settle).to include('say(CTRL.busy, true)')
      expect(app_js).to include("busy: 'A build, rollback, or apply is already running — wait for it to finish.'")
      [app_js, log_js, index_html].each do |asset|
        expect(asset).not_to include('slot_busy')
        expect(asset).not_to include('spawn slot busy')
      end
    end

    it 'failure state: a non-409 failure renders the POST-failure template with the envelope message interpolated, and re-enables' do
      expect(app_js).to include(
        "failure: (name, message) => `Couldn't start the ${name}: ${message}. Check that spm-cache web is still running, then try again.`"
      )
      settle = app_js[/const settle = \(name, ans\) => \{[\s\S]*?\n  \};/]
      expect(settle).to include('say(CTRL.failure(name, data.message || `HTTP ${ans.status}`), true)')
    end

    it 'prohibitions: no markup assignment and no native dialog in the new code; every asset reference in the served index resolves (G-13-1 gate)' do
      %w[innerHTML insertAdjacentHTML document.write outerHTML].each { |api| expect(app_js).not_to include(api) }
      [app_js, log_js].each { |asset| expect(asset).not_to match(/\balert\(|\bconfirm\(|\bprompt\(/) }
      expect(app_js).to include('msg.textContent = text')
      # the skip-link's #surface-main is an in-page anchor, not an asset
      # reference — every OTHER href/src in the document still resolves.
      refs = index_html.scan(/(?:href|src)="([^"]+)"/).flatten.reject { |r| r.start_with?('#') }
      expect(refs).not_to be_empty
      refs.each do |ref|
        expect(ref).to start_with('assets/')
        expect(File.exist?(File.join(asset_dir, File.basename(ref)))).to be(true)
      end
    end

    it 'no new timer and no client clock in the controls code: the state-table poll stays app.js only scheduled work' do
      expect(app_js.scan(/set(?:Timeout|Interval)|requestAnimationFrame/).size).to eq(1)
      expect(app_js).not_to include('Date.now')
      controls = app_js[%r{// -- 11\. build controls[\s\S]*?boot\(\);}]
      expect(controls).not_to include('setTimeout')
      expect(controls).not_to include('setInterval')
    end
  end

  describe 'rollback confirm bar + run-progress coupling (Plan 15-05 Task 2, app-shell port: alert-rail not a Run Log swap)' do
    let(:log_js) { File.read(File.join(asset_dir, 'log.js')) }

    it 'confirm bar structure: grouped + labelled region with the pinned sentence, a danger Confirm and a quiet Cancel, in the alert rail' do
      bar = index_html[%r{<div class="build-confirm"[\s\S]*?</div>}]
      expect(bar).to include('id="build-confirm" role="group" aria-label="Confirm rollback" hidden')
      expect(bar).to include('<span class="build-confirm-text">Restore source mode — this removes proxy packages from the Xcode project</span>')
      expect(bar).to include('<button type="button" class="btn btn-danger" id="ctl-confirm">Confirm</button>')
      expect(bar).to include('<button type="button" class="btn btn-quiet" id="ctl-cancel">Cancel</button>')
      expect(index_html).to include('<div class="build-controls" id="build-controls">') # the topbar row ships VISIBLE (the message slot inside it may hide)
      expect(app_js).to include('const disarmBar = () => { bar.hidden = true; row.hidden = false; };')
      alert_rail = index_html[%r{<div class="alert-rail"[\s\S]*?</div>\s*</div>}]
      expect(alert_rail).to include('id="build-confirm"')
    end

    it 'confirm bar keyboard order: Cancel precedes Confirm in the DOM — focus lands on Cancel and Tab reaches Confirm (A6; D-15 probe catch)' do
      bar = index_html[%r{<div class="build-confirm".*?</div>}m]
      expect(bar.index('id="ctl-cancel"')).to be < bar.index('id="ctl-confirm"')
    end

    it 'confirm copy byte-exact — sentence, Confirm label, Cancel label, em dash included' do
      expect(index_html).to include('Restore source mode — this removes proxy packages from the Xcode project')
      expect(index_html).to include('>Confirm</button>')
      expect(index_html).to include('>Cancel</button>')
    end

    it 'arming: the rollback click hides the row, shows the bar, and moves focus to Cancel — the safe default (A6)' do
      arm = app_js[/ctl\.rollback\.addEventListener\('click', \(\) => \{[\s\S]*?\n  \}\);/]
      expect(arm).to include('row.hidden = true;')
      expect(arm).to include('bar.hidden = false;')
      expect(arm.index('barCancel.focus();')).to be > arm.index('bar.hidden = false;')
    end

    it 'cancelling: Cancel restores the row and returns focus to the rollback button' do
      cancel = app_js[/barCancel\.addEventListener\('click',[\s\S]*?\n  \}\);/]
      expect(cancel).to include('disarmBar();')
      expect(cancel).to include('ctl.rollback.focus();')
    end

    it 'confirming: Confirm disables both bar buttons before the POST, sends the rollback path an empty body, and settles into the row on every answer' do
      confirm = app_js[/barConfirm\.addEventListener\('click',[\s\S]*?\n  \}\);/]
      expect(confirm.index('barConfirm.disabled = true;')).to be < confirm.index('requestPost(')
      expect(confirm).to include('barCancel.disabled = true;')
      expect(confirm).to include("requestPost('/api/rollback', {})")
      expect(confirm).to include('disarmBar();')
      expect(confirm).to include("settle('rollback', ans)")
      expect(app_js).to include("rollback: 'Restoring source mode…'")
    end

    it 'no native dialog function anywhere in the asset set (prohibition 3)' do
      [app_js, log_js, index_html].each { |asset| expect(asset).not_to match(/\balert\(|\bconfirm\(|\bprompt\(/) }
      bar = index_html[%r{<div class="build-confirm"[\s\S]*?</div>}]
      expect(bar).to include('id="ctl-cancel"')
      expect(bar).not_to match(/dialog|modal/i)
    end

    it 'emission points: exactly three dispatch sites at the pre-existing body-line and run-end code points — no traversal, no timer, no second stream, no module import' do
      expect(log_js.scan(/emitProgress\(/).size).to eq(3)
      expect(log_js.scan(/new CustomEvent\('spm-run-progress'/).size).to eq(1)
      expect(log_js.scan(/new EventSource\(/).size).to eq(1)
      append = log_js[/const appendBody = \(data\) => \{[\s\S]*?\n  \};/]
      expect(append).to include("emitProgress('waiting');")
      expect(append).to include("emitProgress('active');")
      %w[app.js log.js].each do |f|
        expect(File.read(File.join(asset_dir, f))).not_to match(/^\s*import\s/m)
      end
      expect(log_js).not_to include('setTimeout')
    end

    it 'waiting phase: a body line byte-equal to the frozen Installer line carries waiting; any following body line carries active (A2)' do
      expect(log_js).to include("const WAIT_LINE = 'Waiting for build lock…';")
      expect(log_js).to include('text === WAIT_LINE')
      installer = File.read(File.join(SPMCache::ROOT, 'lib/spm_cache/installer/build.rb'))
      expect(installer).to include("Core::UI.info 'Waiting for build lock…'")
    end

    it 'ended phase: the run-end path carries ended, from the same facts that flip the identity card' do
      on_run_end = log_js[/const onRunEnd = \(data\) => \{[\s\S]*?\n  \};/]
      expect(on_run_end).to include("emitProgress('ended');")
    end

    it "WR-01: emitProgress no-ops while pinned to a user-selected run — a pinned run's own body-line/run-end milestones must never drive the CLICK-scoped controls row" do
      emit = log_js[/const emitProgress = \(phase\) => \{[\s\S]*?\n  \};/]
      expect(emit).to include('if (pinned) return;')
    end

    it 'listener mapping: app.js maps waiting to the frozen wait string, active to the verb baseline message, ended to idle — buttons re-enabled, message cleared' do
      listener = app_js[/document\.addEventListener\('spm-run-progress'[\s\S]*?\n  \}\);/]
      expect(listener).to include("phase === 'ended'")
      expect(listener).to include('freeze(false); verb = null;')
      expect(listener).to include("say('')")
      expect(listener).to include("phase === 'waiting'")
      expect(listener).to include('say(CTRL.wait)')
      expect(listener).to include("phase === 'active'")
      expect(listener).to include('say(CTRL.inflight[verb])')
      expect(app_js).to include("wait: 'Waiting for build lock…'")
    end

    it 'entry assist: an accepted spawn whose answer reports the lock held shows the waiting message immediately; a free lock shows the verb baseline (the 15-04 snapshot)' do
      settle = app_js[/const settle = \(name, ans\) => \{[\s\S]*?\n  \};/]
      expect(settle.index("data.lock.state === 'held'")).to be < settle.index('say(CTRL.inflight[name])')
      expect(settle).to include('say(CTRL.wait);')
      expect(app_js).to include("wait: 'Waiting for build lock…'")
      expect(log_js).to include("const WAIT_LINE = 'Waiting for build lock…';")
    end

    it 'A3: nothing in the controls code disables a button because lock data says held — disabled derives only from this tab own pending POST or in-flight run' do
      controls = app_js[%r{// -- 11\. build controls[\s\S]*?boot\(\);}]
      expect(controls.scan(/\w+\.disabled = /).uniq.sort)
        .to eq(['applyBtn.disabled = ', 'b.disabled = ', 'barCancel.disabled = ', 'barConfirm.disabled = ',
                'revertBtn.disabled = '])
      freeze_block = controls[/const freeze = \(on\) => \{[\s\S]*?\n  \};/]
      expect(freeze_block).to include('b.disabled = on')
      expect(controls.lines.any? { |l| l.include?('lock') && l.include?('disabled') }).to be(false)
    end
  end

  describe 'app-shell polish (successor to the 14-UI-REVIEW fold, Plan 15-05 Task 3)' do
    let(:log_js) { File.read(File.join(asset_dir, 'log.js')) }

    it 'W1 lives on: the shared button and pill-button rules render labels in the dark foreground on the accent/fail fill (now ≈21:1/≈6:1 under the Grok palette)' do
      btn = styles_css[/\.btn\s*\{[^}]*\}/]
      expect(btn).not_to be_nil
      primary = styles_css[/\.btn-primary\s*\{[^}]*\}/]
      expect(primary).to include('background: var(--c-accent)')
      expect(primary).to include('color: var(--c-bg)')
      pill = styles_css[/\.log-pill-btn\s*\{[^}]*\}/]
      expect(pill).to include('background: var(--c-accent)')
      expect(pill).to include('color: var(--c-bg)')
      danger = styles_css[/\.btn-danger\s*\{[^}]*\}/]
      expect(danger).to include('background: var(--c-fail)')
      expect(danger).to include('color: var(--c-bg)')
    end

    it 'W1 regression: no rule anywhere in the sheet still pairs a pure-white label with the accent or fail fill' do
      expect(styles_css).not_to include('color: #FFFFFF')
      expect(styles_css).not_to include('color: #fff')
    end

    it 'W5 lives on: the switch notice carries a bottom margin — no longer flush against the stream row' do
      sw = styles_css[/\.log-banner,\s*\n\.log-switch\s*\{[^}]*\}/m]
      expect(sw).to include('margin-bottom: var(--space-sm)')
    end

    it 'W3 pills: the follow and filter controls are now STATIC persistent nodes from page load — never created/appended, so the overlay is never wholesale replaced' do
      pill_fn = log_js[/const renderPill = \(\) => \{[\s\S]*?\n  \};/]
      expect(pill_fn).not_to include('overlay.replaceChildren')
      expect(pill_fn).not_to include('overlay.append')
      expect(pill_fn).to include('pauseBtn.textContent = COPY.paused(pending);')
      expect(pill_fn).to include('filterBtn.textContent = COPY.filtered(activeFilter.name);')
    end

    it 'W3 chips: chips reconcile against the anchor set rather than being removed and recreated — the active state is patched in place on the surviving node' do
      chips_fn = log_js[/const renderChips = \(\) => \{[\s\S]*?\n  \};/]
      expect(chips_fn).not_to include('}).forEach((chip) => chip.remove());')
      expect(chips_fn).to include("chip.setAttribute('aria-pressed', isActive ? 'true' : 'false');")
      expect(chips_fn).to include("chip.classList.toggle('log-chip-active', isActive)")
      expect(chips_fn).to include('if (!chip || !chip.isConnected) {')
    end

    it 'W3 focus proof: the reconciliation detaches nothing when unrelated anchors arrive — creation-append is guarded, removal fires only for chips whose anchor left the set' do
      chips_fn = log_js[/const renderChips = \(\) => \{[\s\S]*?\n  \};/]
      expect(chips_fn.index('if (!chip || !chip.isConnected) {')).to be < chips_fn.index('.append(chip);')
      expect(chips_fn).to include('if (!anchors.some((a) => a.chipEl === chip)) chip.remove();')
      expect(chips_fn).not_to include('railPhases.replaceChildren')
      expect(chips_fn).not_to include('railPackages.replaceChildren')
    end

    it 'W4 successor: the sheet carries a small number of documented breakpoints (1080px chrome-trim + 900px stack + reduced-motion) — no undocumented ones' do
      expect(styles_css.scan(/@media/).size).to eq(3)
      expect(styles_css).to include('@media (max-width: 1080px)')
      expect(styles_css).to include('@media (max-width: 900px)')
      expect(styles_css).to include('@media (prefers-reduced-motion: reduce)')
      stack = styles_css[/@media \(max-width: 900px\) \{[\s\S]*?\n\}/]
      expect(stack[/\.log-stream-row\s*\{[^}]*\}/]).to include('flex-direction: column')
      expect(stack[/\.shell\s*\{[^}]*\}/]).to include('grid-template-columns: 1fr')
    end
  end

  # Plan 16-05 Task 1 — the sixth column: native toggle checkboxes,
  # verbatim reason chips, the pending marker, instant persist, poll
  # integrity (A8), and the toggle-save failure line. Unaffected by
  # the app-shell port beyond the ported column widths/checkbox opacity.
  describe 'the Cached column — toggles, reasons, poll integrity (Plan 16-05 Task 1)' do
    it 'the checkbox: checked from saved_cached, disabled from NOT toggleable, aria-label carries the RAW name' do
      row = app_js[/const stateRow = \(p\) => \{[\s\S]*?\n  \};/]
      expect(row).to include('checkbox.checked = p.saved_cached;')
      expect(row).to include('checkbox.disabled = !p.toggleable;')
      expect(row).to include('`Toggle caching for ${p.name}`')
      expect(row).not_to match(/Toggle caching for.*has_macro/)
    end

    it 'the reason chip: five pinned classes only, unrecognised falls back to neutral, renders only on non-toggleable rows' do
      expect(app_js).to include("'pattern-managed': 'neutral'")
      expect(app_js).to include("plugin: 'plugin'")
      expect(app_js).to include("'binary-target': 'neutral'")
      expect(app_js).to include("excluded: 'excluded'")
      expect(app_js).to include("fidelity: 'warn'")
      row = app_js[/const stateRow = \(p\) => \{[\s\S]*?\n  \};/]
      expect(row).to include("REASON_CLASS[p.reason] || 'neutral'")
      expect(row).to include('!p.toggleable && p.reason')
    end

    it 'the pending chip: neutral class, pinned word as text and title, co-renders after the reason chip' do
      row = app_js[/const stateRow = \(p\) => \{[\s\S]*?\n  \};/]
      expect(row).to include("text: 'pending', title: 'pending'")
      expect(row).to include('badge-neutral')
      expect(row.index('p.reason')).to be < row.index('p.pending')
    end

    it 'the change handler POSTs the raw name and the NEW value through the existing POST helper — no new fetch wrapper, no per-row disable on click' do
      row = app_js[/const stateRow = \(p\) => \{[\s\S]*?\n  \};/]
      expect(row).to include("checkbox.addEventListener('change', () => postToggle(p.name, checkbox.checked));")
      post = app_js[/const postToggle = \(name, cached\) => \{[\s\S]*?\n  \};/]
      expect(post).to include("requestPost('/api/toggle', { package: name, cached })")
      expect(app_js.scan(/const requestPost = /).size).to eq(1)
      expect(row).not_to include('checkbox.disabled = true')
    end

    it 'poll integrity: the counter increments before the request and decrements in the completion path; the poll loop skips the whole refresh while it is non-zero; Refresh is not routed through the skip' do
      post = app_js[/const postToggle = \(name, cached\) => \{[\s\S]*?\n  \};/]
      expect(post.index('toggleInFlight += 1;')).to be < post.index('requestPost(')
      expect(post).to include('.finally(() => { toggleInFlight -= 1; });')
      loop_fn = app_js[/const loop = async \(\) => \{[\s\S]*?\n    \};/]
      expect(loop_fn).to include('if (toggleInFlight === 0) await refreshState();')
      expect(app_js).to include(
        "byId('state-refresh').addEventListener('click', () => { clearToggleFailure(); refreshState(); });"
      )
    end

    it 'the failure line: pinned template with package + message, re-inserted above the table on every render, cleared by success or Refresh' do
      expect(app_js).to include(
        "const toggleFailureCopy = (name, message) =>\n    `Couldn't save the toggle for ${name}: " \
        '${message}. Check that spm-cache web is still running, then try again.`;'
      )
      render = app_js[/const renderState = \(envelope\) => \{[\s\S]*?\n  \};/]
      expect(render).to include('showToggleFailure(body);')
      post = app_js[/const postToggle = \(name, cached\) => \{[\s\S]*?\n  \};/]
      expect(post).to include('clearToggleFailure(); return;')
      expect(post).to include("showToggleFailure(byId('state-body'));")
      show = app_js[/const showToggleFailure = \(body\) => \{[\s\S]*?\n  \};/]
      expect(show).to include("body.querySelector('.toggle-failure')?.remove();")
      expect(show).to include("class: 'toggle-failure'")
    end

    it 'prohibition sweep: no markup-assignment API, no dialog, no new timer, no clock, no role=switch, no master checkbox, no per-row apply button' do
      %w[innerHTML insertAdjacentHTML document.write outerHTML].each { |api| expect(app_js).not_to include(api) }
      expect(app_js).not_to match(/\balert\(|\bconfirm\(|\bprompt\(/)
      expect(app_js.scan(/set(?:Timeout|Interval)|requestAnimationFrame/).size).to eq(1)
      expect(app_js).not_to include('Date.now')
      expect(app_js).not_to match(/role=["']switch["']/)
      expect(app_js.scan(/\.type = 'checkbox'/).size).to eq(1)
      row = app_js[/const stateRow = \(p\) => \{[\s\S]*?\n  \};/]
      expect(row).not_to include('Apply')
    end
  end

  # Plan 16-05 Task 2 — the unsaved-changes bar: the comment-loss
  # honesty sentence, Apply now, Revert all, and the busy-string/
  # freeze-set amendments (A4/A5). The app-shell port moved this bar
  # from create/destroy-per-render to static show/hide (context
  # decision 4) — buildSyncBar/barFrozen no longer exist.
  describe 'the unsaved-changes bar (Plan 16-05 Task 2, app-shell port: static show/hide)' do
    it 'existence: the static bar toggles hidden only when >=1 row is pending; the message slot resets blank every render (matches the old fresh-build-every-poll behavior)' do
      render = app_js[/const renderState = \(envelope\) => \{[\s\S]*?\n  \};/]
      expect(render).to include('updateSyncBar(pendingCount);')
      sync_bar_fn = app_js[/const updateSyncBar = \(pendingCount\) => \{[\s\S]*?\n  \};/]
      expect(sync_bar_fn).to include("byId('state-sync-bar').hidden = pendingCount === 0;")
      expect(sync_bar_fn).to include("saySync('');")
      expect(app_js).not_to include('const buildSyncBar')
      expect(app_js).not_to include('barFrozen')
    end

    it 'structure and DOM order (static markup): the honesty sentence, then Revert all, then Apply now, then the hidden message slot' do
      bar = index_html[%r{<div class="state-sync-bar"[\s\S]*?</div>\s*</div>}]
      expect(bar.index('state-sync-text')).to be < bar.index('id="sync-revert"')
      expect(bar.index('id="sync-revert"')).to be < bar.index('id="sync-apply"')
      expect(bar.index('id="sync-apply"')).to be < bar.index('id="sync-message"')
    end

    it 'copy: the honesty sentence, both button labels, both in-flight messages and both failure templates are pinned byte-exact' do
      expect(index_html).to include(
        'Changes are saved but not applied yet. spm-cache.yml is rewritten on every change — '\
        'hand-written comments in the file are not preserved.'
      )
      expect(index_html).to include('id="sync-revert">Revert all</button>')
      expect(index_html).to include('id="sync-apply">Apply now</button>')
      expect(app_js).to include("apply: 'Applying…', revert: 'Reverting…',")
      expect(app_js).to include(
        "revertFailure: (message) => `Couldn't revert the changes: ${message}. " \
        'Check that spm-cache web is still running, then try again.`,'
      )
    end

    it 'no per-row apply or master checkbox exists anywhere; #sync-apply/#sync-revert are the only Apply/Revert controls in the static markup' do
      expect(index_html.scan(/id="sync-apply"/).size).to eq(1)
      expect(index_html.scan(/id="sync-revert"/).size).to eq(1)
      expect(app_js.scan(/\.type = 'checkbox'/).size).to eq(1)
    end

    it 'the busy amendment: ONE three-verb CTRL.busy constant; the two-verb 15 string appears nowhere in the assets' do
      expect(app_js.scan(/busy:\s*'/).size).to eq(1)
      expect(app_js).to include("busy: 'A build, rollback, or apply is already running — wait for it to finish.'")
      [app_js, styles_css, index_html].each do |asset|
        expect(asset).not_to include('A build or rollback is already running — wait for it to finish.')
      end
    end

    it 'the freeze set: the three topbar controls freeze Apply now too — #sync-apply is a static node, so freeze() is the ONLY writer of its disabled state (no re-apply needed on show)' do
      freeze_fn = app_js[/const freeze = \(on\) => \{[\s\S]*?\n  \};/]
      expect(freeze_fn).to include("byId('sync-apply')")
      expect(freeze_fn).to include('applyBtn.disabled = on;')
    end

    it 'the click handlers bind ONCE to the static nodes at module top level (not rebuilt per render)' do
      expect(app_js).to include("byId('sync-revert').addEventListener('click', clickRevert);")
      expect(app_js).to include("byId('sync-apply').addEventListener('click', clickApply);")
    end

    it 'apply behavior: disables both buttons before the POST; success shows Applying… and freezes; busy/failure re-enable with the right templates' do
      click = app_js[/const clickApply = \(\) => \{[\s\S]*?\n  \};/]
      expect(click.index('applyBtn.disabled = true;')).to be < click.index('revertBtn.disabled = true;')
      expect(click.index('revertBtn.disabled = true;')).to be < click.index("requestPost('/api/apply', {})")
      expect(click.index('ans.status === 409')).to be < click.index('!ans.ok')
      expect(click).to include('saySync(CTRL.busy, true);')
      expect(click).to include("saySync(CTRL.failure('apply', data.message || `HTTP ${ans.status}`), true);")
      expect(click).to include('saySync(CTRL.inflight.apply);')
      expect(click).to include('freeze(true);')
    end

    it 'revert behavior: disables both buttons, clears the message and re-enables on success WITHOUT touching the bar or a pending marker; renders the revert-failure template on failure' do
      click = app_js[/const clickRevert = \(\) => \{[\s\S]*?\n  \};/]
      expect(click.index('applyBtn.disabled = true;')).to be < click.index("requestPost('/api/revert', {})")
      expect(click).to include('saySync(CTRL.inflight.revert);')
      expect(click).to include('saySync(CTRL.revertFailure(data.message || `HTTP ${ans.status}`), true);')
      expect(click).to include("saySync('');")
      expect(click).not_to match(/bar\.(hidden|remove)/)
      expect(click).not_to match(/\.pending\b|['"]pending['"]/)
    end

    it 'the exit: the run-progress ended milestone clears the bar message; the bar itself disappears only via a subsequent render seeing no pending rows' do
      listener = app_js[/document\.addEventListener\('spm-run-progress'[\s\S]*?\n  \}\);/]
      expect(listener).to include("if (phase === 'ended') { freeze(false); verb = null; say(''); saySync(''); return; }")
    end

    it 'the sheet: mirrors the confirm/alert-bar geometry with the warn wash fill' do
      bar = styles_css[/\.state-sync-bar\s*\{[^}]*\}/]
      expect(bar).to include('display: flex')
      expect(bar).to include('background: var(--wash-warn)')
      expect(app_js).to include('const saySync = (text, error) => {')
    end
  end
end
