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

    it 'references exactly three RELATIVE assets: styles.css, cytoscape.min.js, app.js (module)' do
      expect(index_html).to include('href="styles.css"')
      expect(index_html).to include('src="cytoscape.min.js"')
      expect(index_html).to include('type="module"')
      expect(index_html).to include('src="app.js"')
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
      expect(app_js).to include("' to populate the cache, then '")
      expect(app_js).to include("class: 'cmd'")
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
      expect(app_js).to include("' to generate graph.json, then '")
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
  end
end
