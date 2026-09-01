# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

require_relative 'support/web_server_boot'

# Plan 13-03 — the dashboard frontend, pinned as SERVED and FILE bytes.
# This repo runs no JavaScript in CI: every contract below is a
# byte-level pin (the HTML the server serves, the asset files' exact
# contents), cross-checked by the manual browser walkthrough in
# 13-VALIDATION. The 13-UI-SPEC is BINDING: copy strings, color values,
# spacing multiples, and typography roles are pinned verbatim.
RSpec.describe 'spm-cache web dashboard frontend (Plan 13-03)' do
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

    it 'carries the page title and the three panel titles in locked DOM order' do
      expect(index_html).to include('<title>spm-cache</title>')
      expect(index_html).to include('<h2>Cache State</h2>')
      expect(index_html).to include('<h2>Doctor</h2>')
      expect(index_html).to include('<h2>Dependency Graph</h2>')
      expect(index_html.index('Cache State'))
        .to be < index_html.index('<h2>Doctor</h2>')
      expect(index_html.index('<h2>Doctor</h2>'))
        .to be < index_html.index('Dependency Graph')
    end

    it 'buttons: Refresh on Cache State + Dependency Graph, Run Doctor on Doctor' do
      expect(index_html.scan(%r{<button[^>]*>Refresh</button>}).size).to eq(2)
      expect(index_html.scan(%r{<button[^>]*>Run Doctor</button>}).size).to eq(1)
    end

    it 'each panel header has a stamp span; each panel body starts with a muted Loading… line' do
      expect(index_html.scan(/class="stamp"/).size).to eq(3)
      expect(index_html.scan(%r{<p class="loading">Loading…</p>}).size).to eq(3)
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

    it 'graph panel body carries the canvas mount and the legend element' do
      expect(index_html).to include('id="graph-legend"')
      expect(index_html).to include('id="cy-canvas"')
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
      expect(replace_at).to be < boot_at # order pinned textually; 13-VALIDATION re-checks in a browser
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
    it 'renders the full-page token-invalid copy replacing all panels' do
      expect(app_js)
        .to include("This page's access token is no longer valid. Restart spm-cache web and open the URL it prints.")
    end

    it 'consumes the {status,data} envelope and throws the server message' do
      expect(app_js).to include("envelope.status === 'error'")
      expect(app_js).to include('envelope.data && envelope.data.message')
    end
  end

  describe 'app.js source contract — state table (DASH-01)' do
    it 'pins the status→class vocabulary exactly' do
      expect(app_js).to include("hit: 'ok', missed: 'warn', ignored: 'neutral', excluded: 'excluded', plugin: 'plugin'")
    end

    it 'renders the five locked columns' do
      expect(app_js).to include("'Package', 'Config', 'Size', 'State', 'Fidelity'")
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

    it 'empty state copy verbatim, with .cmd accent spans' do
      expect(app_js).to include("'No cached packages yet'")
      expect(app_js).to include("'spm-cache build'")
      expect(app_js).to include("' to populate the cache, then Refresh.'")
      expect(app_js).to include("class: 'cmd'")
    end

    it 'empty-state Refresh is plain text — accent .cmd is reserved for command references (review IN-02)' do
      expect(app_js).not_to include("cmd('Refresh')")
      expect(app_js).to include("' to populate the cache, then Refresh.'")
      expect(app_js).to include("' to generate graph.json, then Refresh.'")
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

  describe 'app.js source contract — doctor panel (DASH-02)' do
    it 'pins the marker vocabulary reused verbatim from doctor.rb' do
      expect(app_js).to include("ok: '✓', warn: '!', fail: '✗'")
    end

    it 'empty state copy verbatim' do
      expect(app_js).to include("'Doctor has not run yet'")
      expect(app_js).to include("'Select Run Doctor to check your environment.'")
    end

    it 'cached stamp derives from the envelope generated_at (em dash, HH:MM:SS)' do
      expect(app_js).to match(/Cached — generated at \$\{fmtHMS\([^)]*\)\}/)
    end

    it 'summary line mirrors the CLI vocabulary from data.summary (not recounted)' do
      expect(app_js)
        .to include('${summary.ok} ok · ${summary.warnings} warnings · ${summary.failures} failures')
    end

    it 'Run Doctor swaps the label to Running… and back, firing ?run=1' do
      expect(app_js).to include("'/api/doctor?run=1'")
      expect(app_js).to include("'/api/doctor'")
      expect(app_js).to include("'Running…'")
      expect(app_js).to include("'Run Doctor'")
    end

    it 'fix hints render as a ↳ second line for non-ok checks that carry one' do
      expect(app_js).to include('↳ ${check.fix_hint}')
      expect(app_js).to include("check.status !== 'ok'")
    end

    it 'doctor is on-demand only — the ONLY timer in the file is the state poll' do
      expect(app_js.scan(/window\.setTimeout/).size).to eq(1)
    end

    it 'doctor fetch failures render the panel-name error copy' do
      expect(app_js).to include("'Doctor', err.message")
    end
  end

  describe 'app.js source contract — graph panel (DASH-03)' do
    it 'empty state copy verbatim, naming the generating command' do
      expect(app_js).to include("'No dependency graph yet'")
      expect(app_js).to include("'spm-cache use'")
      expect(app_js).to include("' to generate graph.json, then Refresh.'")
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

  describe 'app.js locked budget' do
    it 'stays within the 300–400 LOC vanilla-JS budget' do
      expect(app_js.lines.length).to be >= 300
      expect(app_js.lines.length).to be <= 400
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
      # app.js membership is pinned in Task 2, once the file exists.
      expect(files).to include('lib/spm_cache/web/assets/styles.css')
    end
  end

  describe 'styles.css design tokens (13-UI-SPEC locked)' do
    it 'declares the full spacing scale, every value a multiple of 4' do
      tokens = styles_css.scan(/--space-[a-z0-9]+:\s*(\d+)px/).flatten.map(&:to_i)
      expect(tokens).to contain_exactly(4, 8, 16, 24, 32, 48, 64)
      expect(tokens).to all(be_truthy)
      tokens.each { |px| expect(px % 4).to eq(0) }
    end

    it 'declares every locked color token verbatim' do
      {
        '--c-bg' => '#0D1117', '--c-panel' => '#161B22', '--c-border' => '#30363D',
        '--c-accent' => '#2196F3', '--c-fail' => '#F44336', '--c-text' => '#E6EDF3',
        '--c-muted' => '#8B949E', '--c-ok' => '#4CAF50', '--c-warn' => '#FF9800',
        '--c-neutral' => '#9E9E9E', '--c-excluded' => '#607D8B',
        '--c-plugin' => '#3F51B5', '--c-macro' => '#9C27B0'
      }.each { |token, value| expect(styles_css).to include("#{token}: #{value}") }
    end

    it 'declares both font stacks: system + ui-monospace' do
      expect(styles_css).to include('--font-system: -apple-system, BlinkMacSystemFont, sans-serif')
      expect(styles_css).to include('--font-mono: ui-monospace, SFMono-Regular, Menlo, monospace')
    end

    it 'implements the four typography roles (20/16/14/12px, weights 400/600 only, no italics)' do
      %w[20px 16px 14px 12px].each { |size| expect(styles_css).to include("font-size: #{size}") }
      expect(styles_css).to include('font-weight: 400')
      expect(styles_css).to include('font-weight: 600')
      expect(styles_css).not_to match(/font-weight:\s*(300|500|700)/)
      expect(styles_css).not_to include('italic')
    end

    it 'pins the layout: 48px header bar, 1280px column, 64px top margin, 8px panel radius, 480px canvas' do
      expect(styles_css).to include('--space-2xl: 48px')
      expect(styles_css).to include('height: var(--space-2xl)')
      expect(styles_css).to include('max-width: 1280px')
      expect(styles_css).to include('margin: var(--space-3xl)')
      expect(styles_css).to include('border-radius: 8px')
      expect(styles_css).to include('height: 480px')
    end

    it 'buttons: solid accent fill, white text, accent keyboard focus ring' do
      expect(styles_css).to include('background: var(--c-accent)')
      expect(styles_css).to include('color: #FFFFFF')
      expect(styles_css).to include('outline: 2px solid var(--c-accent)')
    end

    it 'badges: colored text on a 10%-alpha fill of the same color, 4px/8px padding, 4px radius' do
      expect(styles_css).to include('rgba(76, 175, 80, 0.1)')
      expect(styles_css).to include('rgba(255, 152, 0, 0.1)')
      expect(styles_css).to include('rgba(244, 67, 54, 0.1)')
      expect(styles_css).to include('rgba(158, 158, 158, 0.1)')
      expect(styles_css).to include('rgba(96, 125, 139, 0.1)')
      expect(styles_css).to include('rgba(63, 81, 181, 0.1)')
      expect(styles_css).to include('padding: var(--space-xs) var(--space-sm)')
      expect(styles_css).to include('border-radius: 4px')
    end

    it 'table: full width, sm cell padding, 1px border row rules, ellipsized cells, no inner scroll' do
      expect(styles_css).to include('width: 100%')
      expect(styles_css).to include('table-layout: fixed')
      expect(styles_css).to include('padding: var(--space-sm)')
      expect(styles_css).to include('border-bottom: 1px solid var(--c-border)')
      expect(styles_css).to include('text-overflow: ellipsis')
      expect(styles_css).not_to include('max-height')
    end

    it 'mono 12px for sizes, fidelity values, stamps, and the port label; fix hints indent 24px' do
      expect(styles_css).to include('font-family: var(--font-mono)')
      expect(styles_css).to include('.mono')
      expect(styles_css).to include('.fix-hint')
      expect(styles_css).to include('padding-left: var(--space-lg)')
    end

    it 'accent text color appears only on .cmd command references — never on table text' do
      expect(styles_css).to include('.cmd')
      expect(styles_css.scan(/color: var\(--c-accent\)/).size).to eq(1)
    end

    it 'check-line ellipsis actually ellipsizes: flex children allow shrinking (review IN-04)' do
      %w[.check-name .check-message].each do |rule|
        block = styles_css[/#{Regexp.escape(rule)}\s*\{[^}]*\}/]
        expect(block).to include('min-width: 0')
      end
    end
  end
  # Plan 14-04 — the Run Log panel and its second ES module, pinned
  # the same way: SERVED bytes for the route rows, FILE bytes for
  # every copy string and mechanic. The 14-UI-SPEC is BINDING and its
  # Prohibitions section is testable here: no markup-writing APIs, no
  # client clock, no scheme-absolute refs, no color-only status.
  describe 'log.js + Run Log panel (Plan 14-04)' do
    let(:log_js) { File.read(File.join(asset_dir, 'log.js')) }

    describe 'serving + module registration' do
      it 'serves /assets/log.js as JavaScript, referenced RELATIVE after app.js, and ships in the gem' do
        res = served('/assets/log.js')
        expect(res.code).to eq('200')
        expect(res['Content-Type']).to eq('application/javascript')
        # G-13-1: the relative assets/<name> form resolves through the
        # router's /assets/* arm. log.js rides after app.js and needs
        # no ordering — the modules share only sessionStorage, never
        # globals.
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
        expect(log_js).to include("new EventSource('/api/events?token=' + token)")
      end

      it 'registers named listeners for hello/entry/switch/notice — the module ships whole' do
        %w[hello entry switch notice].each do |name|
          expect(log_js).to include("addEventListener('#{name}'")
        end
      end
    end

    describe 'connection states' do
      it 'pins the three pill states; CLOSED replaces main content with the locked token-invalid page' do
        expect(log_js).to include("'● connecting…'")
        expect(log_js).to include("'● connected'")
        expect(log_js).to include("'↻ reconnecting…'")
        expect(log_js).to include('readyState === EventSource.CLOSED')
        expect(log_js)
          .to include("This page's access token is no longer valid. Restart spm-cache web and open the URL it prints.")
        expect(log_js).to include("querySelector('main.content')")
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
        expect(log_js).to include(' · completed ${relative(endIso)} ago')
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

      it 'muted Loading… before the first stream byte; no card until hello' do
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
    end

    describe 'identity card (D-06/D-11)' do
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
      it 'Run Log panel FIRST with the a11y-complete skeleton' do
        expect(index_html.index('<h2>Run Log</h2>')).to be < index_html.index('<h2>Cache State</h2>')
        expect(index_html).to include('<div class="log-viewport" id="log-viewport" role="log" aria-live="off" aria-label="Run output" tabindex="0"></div>')
        expect(index_html).to include('>Phases</div>')
        expect(index_html).to include('>Packages</div>')
        expect(index_html).to include('id="log-overlay"')
        expect(index_html).to include('id="log-banner" role="alert"')
        # exactly two polite live regions: the card status flip + the pill
        expect(index_html.scan(/aria-live="polite"/).size).to eq(2)
      end

      it 'styles: log rules on the existing sheet — fixed-height viewport, pre-wrap mono lines, ONE accent-text home' do
        expect(styles_css.scan(/height: 480px/).size).to eq(3) # graph canvas + log viewport + anchor rail
        expect(styles_css).to include('.log-viewport')
        expect(styles_css).to include('white-space: pre-wrap')
        expect(styles_css).to include('background: var(--c-bg)')
        # A3: accent TEXT stays a single declaration; the .cmd group
        # carries the sanctioned liveness surfaces (never verdicts) —
        # 14-05 widens it once more for the active anchor chip (D-09's
        # accent-badge style), preserving the eq(1) count invariant.
        expect(styles_css.scan(/color: var\(--c-accent\)/).size).to eq(1)
        expect(styles_css).to match(/\.cmd,\s*\.log-live,\s*\.log-chip-active\s*\{/)
      end
    end

    describe 'follow/pause + banners + a11y (Plan 14-04 Task 2)' do
      it 'follow pins instantly: scrollTop = scrollHeight on append, no smooth behavior, ANY upward scroll disengages' do
        expect(log_js).to include('viewport.scrollTop = viewport.scrollHeight')
        expect(log_js).not_to include('smooth')
        expect(log_js).not_to include('scrollIntoView')
        expect(log_js).to include('viewport.scrollTop < lastScrollTop')
      end

      it 'the pause pill is ONE button carrying the whole label; {N} live and uncapped; activation re-engages + clears + removes' do
        expect(log_js).to include('paused: (n) => `paused — ${n} new lines · jump to live`')
        expect(log_js).to include('if (!replaying && !follow && pending >= 1)')
        expect(log_js).to include('pending += 1')
        expect(log_js).to include('pending = 0')
        expect(log_js).to include("type: 'button'")
        expect(log_js).to include('text: COPY.paused(pending)')
      end

      it 'during initial replay the pill never shows; follow engages at completion (D-01/D-13)' do
        expect(log_js).to include('if (replaying && atBottom()) replaying = false;')
        expect(log_js).to include("viewport.addEventListener('scroll'")
        expect(log_js).to include('const atBottom = () =>')
      end

      it 'non-zero run_end → sticky Run failed banner with the jump button, role=alert, NO dismiss control' do
        expect(log_js).to include('failedBanner: (status) => `Run failed — exit status ${status}`')
        expect(log_js).to include("jumpToError: 'Jump to first error'")
        expect(log_js).to include('bannerEl.hidden = false')
        expect(log_js).not_to match(/dismiss/i)
        expect(log_js).not_to include("'Close'")
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
        expect(log_js).to match(/resetForRun\(data\.run, \{ followOn: true \}\)/)
      end

      it 'focus-visible accent rings cover pill/chip/select controls; native button only; pill name = full label' do
        %w[.log-pill-btn .log-chip .log-runs-select].each do |rule|
          expect(styles_css).to include("#{rule}:focus-visible")
        end
        expect(styles_css).to include('outline: 2px solid var(--c-accent)')
        expect(log_js.scan(/el\('button'/).size).to be >= 2 # the pause pill + the jump button — native controls only
      end

      it 'teardown safety: the token-invalid replacement stops every stream handler (app.js bail-out guard)' do
        expect(log_js).to include('let dead = false;')
        expect(log_js.scan(/if \(!alive\(\)\) return;/).size).to be >= 4
        expect(log_js).to include("byId('log-viewport')")
      end
    end
  end
  # Plan 14-05 Task 1 — the anchor rail (D-07/D-08), jump + filter
  # dimming (D-09), the filter pill, and banner piercing (D-10). Same
  # discipline as 14-04: FILE bytes pin every mechanic. The 14-UI-SPEC
  # Interaction rows and assumptions A5 (dim, never hide) and A10
  # (dedupe by name, first position) are BINDING here.
  describe 'log.js anchor rail + filter + piercing (Plan 14-05)' do
    let(:log_js) { File.read(File.join(asset_dir, 'log.js')) }

    it 'chips: package names verbatim + the four phase markers; duplicates dedupe by name, first position wins (A10); no chips for no-line or unknown events' do
      expect(log_js).to include("addAnchor('package', name, divider)")
      expect(log_js).to include("addAnchor('phase', name, divider)")
      # A10: dedupe-by-name, first position wins — defensive only in the
      # frozen Phase-12 vocabulary
      expect(log_js).to include('if (anchors.some((a) => a.kind === kind && a.name === name)) return;')
      # addAnchor exists ONLY inside the divider branch: the 14-04 taxonomy
      # rows already pin package_end/run_start/run_end/sh/unknown keys to
      # no-line returns — chips render as their anchor events arrive, no
      # placeholders (D-07)
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

    it 'package filter: the package_start..package_end segment stays primary (inclusive); every other line — before the first anchor included — takes the dim class; NO line leaves the DOM (A5)' do
      expect(log_js).to include('const matches = (line) => {')
      expect(log_js).to include('seg.pkg === activeFilter.name')
      expect(log_js).to include("classList.toggle('log-dim', !matches(node));")
      apply = log_js[/const applyFilter = \(\) => \{[\s\S]*?\n  \};/]
      expect(apply).to include("classList.toggle('log-dim', !matches(line));")
      expect(apply).not_to include('remove') # A5: dim, never hide — no DOM removal in the filter path
    end

    it 'phase filter: from the marker to the line before the next phase marker OR package_start (segment rules verbatim)' do
      expect(log_js).to include('seg.phase === activeFilter.name')
      expect(log_js).to include('segPackage = name;')
      expect(log_js).to include('segPhase = null;') # a package_start ends the phase segment
      expect(log_js).to include('SEG.set(divider, { pkg: name, phase: null });')
      expect(log_js).to include('SEG.set(divider, { pkg: null, phase: name });')
    end

    it 'filter pill: ONE button carrying filtered: {name}; activation clears the filter with the view put; 240px max-width + ellipsis + tooltip' do
      expect(log_js).to include('filtered: (name) => `filtered: ${name}`')
      expect(log_js).to include('if (activeFilter) {')
      expect(log_js).to include('text: COPY.filtered(activeFilter.name),')
      expect(log_js).to include('title: COPY.filtered(activeFilter.name),')
      expect(log_js).to include("fp.addEventListener('click', clearFilter);")
      expect(styles_css).to match(/\.log-filter-pill\s*\{[^}]*max-width: 240px[^}]*text-overflow: ellipsis/)
    end

    it 'active chip: accent badge style (text on 10%-alpha fill) + aria-pressed=true; clicking the ACTIVE chip clears the filter with the view staying put' do
      expect(log_js).to include("chip.setAttribute('aria-pressed', isActive ? 'true' : 'false');")
      expect(log_js).to match(%r{if \(isActive\) \{\s*clearFilter\(\); //})
      expect(styles_css).to include('.log-chip-active')
      expect(styles_css).to include('rgba(33, 150, 243, 0.1)')
      # A3: the active chip joins the ONE accent-text declaration's group —
      # still exactly one accent-color declaration on the sheet
      expect(styles_css).to match(/\.cmd,\s*\.log-live,\s*\.log-chip-active\s*\{/)
      expect(styles_css.scan(/color: var\(--c-accent\)/).size).to eq(1)
    end

    it 'piercing: the banner renders regardless of filter state — its slot sits outside the filtered viewport and its render path never reads filter state (D-10)' do
      expect(index_html.index('id="log-banner"')).to be < index_html.index('id="log-viewport"')
      on_run_end = log_js[/const onRunEnd = \(data\) => \{[\s\S]*?\n  \};/]
      expect(on_run_end).to include("showBanner('failed', status)")
      expect(on_run_end).not_to include('activeFilter')
      show_banner = log_js[/const showBanner = \(kind, status\) => \{[\s\S]*?\n  \};/]
      expect(show_banner).not_to include('activeFilter')
      # the dim walk is scoped to the viewport's own lines — the banner is
      # not a line and can never take the dim class
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
end
