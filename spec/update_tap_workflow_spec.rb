# frozen_string_literal: true

require 'spec_helper'

# Structural regression spec for the tap-publish workflow (Phase 11,
# REL-04..09): parse .github/workflows/update-tap.yml with strict Psych and
# pin every release-automation property the phase requires — deploy-key auth,
# the integrity-gated tarball download, anchored formula edits with
# exactly-one enforcement, the explicit no-diff publish branch, and the
# injection rule (trigger contexts reach run bodies through env mappings
# only).
#
# Psych parses the workflow's unquoted `on:` key as boolean true (verified on
# Ruby 3.2.3 / Psych 5.0.1), so the trigger map is reached via workflow[true];
# workflow['on'] is nil. Structure is asserted through the parsed tree;
# shell-body properties are asserted with line-anchored regexes over the step
# text so a prose comment (leading #) can never satisfy a structural claim.
RSpec.describe '.github/workflows/update-tap.yml' do
  let(:path) { '.github/workflows/update-tap.yml' }
  let(:workflow) { YAML.safe_load_file(path, permitted_classes: [], aliases: false) }
  let(:text) { File.read(path) }
  let(:triggers) { workflow[true] } # NOT workflow['on'] — nil under Psych (Pitfall 4)
  let(:jobs) { workflow.fetch('jobs') }
  let(:update_tap) { jobs.fetch('update-tap') }
  let(:steps) { update_tap.fetch('steps') }
  let(:run_steps) { steps.select { |s| s.key?('run') } }
  let(:verify_publish) do
    jobs['verify-publish'] or
      raise "#{path} declares no verify-publish job — spec slicing broken"
  end
  let(:verify_steps) { verify_publish.fetch('steps') }

  # Loud-failure slicing: locate steps by stable markers and raise naming the
  # file instead of asserting against nil (action_spec.rb:25-28 idiom).
  def step_by_id(id)
    steps.find { |s| s['id'] == id } or
      raise "#{path} has no step with id '#{id}' — spec slicing broken"
  end

  def run_step_by_marker(marker)
    run_steps.find { |s| s['run'].include?(marker) } or
      raise "#{path} has no run step containing '#{marker}' — spec slicing broken"
  end

  it 'parses as strict YAML with the Psych on-key quirk handled' do
    expect(workflow).to be_a(Hash)
    expect(workflow.fetch('name')).to eq('Update Homebrew Tap')
    expect(workflow['on']).to be_nil,
                              'unquoted on: parses as boolean true under Psych — read triggers via workflow[true]'
    expect(triggers).to be_a(Hash)
    expect(jobs).to be_a(Hash)
  end

  it 'pins the trigger surface to release[published] + workflow_dispatch (no fork-PR spoofing)' do
    expect(triggers.keys.sort).to eq(%w[release workflow_dispatch]),
                                  'trigger set pinned — pull_request would let fork PRs run the publish path'
    expect(triggers.dig('release', 'types')).to eq(['published'])
  end

  it 'exposes a dispatch retry surface with a required string tag input (REL-09)' do
    dispatch = triggers['workflow_dispatch']
    expect(dispatch).to be_a(Hash), 'workflow_dispatch trigger missing — no retry without re-publishing'
    tag = dispatch.dig('inputs', 'tag') or
      raise "#{path} dispatch trigger declares no tag input — spec slicing broken"
    expect(tag['type']).to eq('string')
    expect(tag['required']).to eq(true)
    expect(tag['description']).to be_a(String)
    expect(tag['description']).not_to be_empty
  end

  it 'queues concurrent runs and keeps the ambient token minimal (REL-05)' do
    conc = workflow['concurrency']
    expect(conc).to be_a(Hash),
                    'workflow-level concurrency group missing — two releases would race on the tap push'
    expect(conc['group']).to eq('update-tap')
    expect(conc['cancel-in-progress']).to eq(false),
                                          'cancel-in-progress must be false: queue, never cancel mid-push'
    expect(workflow['permissions']).to eq('contents' => 'read')
  end

  it 'runs the edit job on ubuntu-latest and the verify job on macOS (GNU vs BSD sed)' do
    expect(jobs.keys.sort).to eq(%w[update-tap verify-publish])
    expect(update_tap['runs-on']).to eq('ubuntu-latest')
    expect(verify_publish['runs-on']).to match(/macos/),
                                         'post-publish verification installs a macOS-only formula'
  end

  it 'gates verify-publish on update-tap and plumbs the resolved version (REL-08)' do
    expect(verify_publish['needs']).to eq('update-tap')
    expect(update_tap['outputs']).to eq('version' => '${{ steps.version.outputs.version }}'),
                                     'the resolve step version must become a job output'
    env = verify_publish.fetch('env')
    expect(env['EXPECTED_VERSION']).to eq('${{ needs.update-tap.outputs.version }}')
    expect(env['HOMEBREW_NO_AUTO_UPDATE']).to eq('1'),
                                              'quoted string 1 — skip the slow nondeterministic brew update'
  end

  it 'installs the published formula exactly as a user would (REL-08)' do
    install = verify_steps.find { |s| s['run'].to_s.include?('brew install') } or
      raise "#{path} verify job has no brew install step"
    expect(install['run']).to match(%r{^\s*brew install phuongddx/spm-cache/spm-cache\b}),
                              'user/repo/formula form — implicitly taps the published tap'
  end

  it 'asserts the installed version equals the released version whole-string (REL-08)' do
    assertion = verify_steps.find { |s| s['run'].to_s.include?('EXPECTED_VERSION') } or
      raise "#{path} verify job has no version assertion step"
    body = assertion.fetch('run')
    expect(body.lines.first.strip).to eq('set -euo pipefail')
    expect(body).to match(/^\s*brew list --versions /), 'log the installed versions for the run record'
    expect(body).to match(/^\s*ACTUAL="\$\(spm-cache --version \| tr -d '\[:space:\]'\)"/),
                    'capture the installed version, whitespace deleted'
    expect(body).to match(/^\s*echo "installed: \$\{ACTUAL\}, expected: \$\{EXPECTED_VERSION\}"/)
    expect(body).to match(/^\s*\[ "\$ACTUAL" = "\$EXPECTED_VERSION" \]/),
                    'whole-string equality — a mismatching version must fail the release run red'
  end

  it 'keeps the verify job anonymous — no token, secret, or app reference' do
    expect(verify_publish.to_yaml).not_to match(/token|secret/i),
                                          'the tap is public — the verify job needs no credentials at all'
  end

  it 'resolves the tag and version from the release ref via GITHUB_OUTPUT' do
    body = step_by_id('version').fetch('run')
    expect(body).to match(/^\s*TAG="\$GITHUB_REF_NAME"/),
                    'release path: the tag comes from the ref-name ambient variable'
    tag_re_line = body.lines.find { |l| l.start_with?('tag_re=') } or
      raise "#{path} resolve step declares no strict tag shape gate — spec slicing broken"
    expect(tag_re_line).to include('^v[0-9]+\\.[0-9]+\\.[0-9]+([-+][0-9A-Za-z.-]+)?$'),
                           'strict semver shape — the old v[0-9]* glob accepted v1.2.3&calc (legal git tag, sed metacharacter)'
    expect(body).to match(/^\s*if ! \[\[ "\$TAG" =~ \$tag_re \]\]; then/),
                    'the shape gate must be the bash-regex check'
    expect(body).to match(/^\s*echo "::error::tag '\$\{TAG\}' must look like v0\.4\.0"; exit 1/),
                    'shape failure must emit a red error annotation'
    expect(body).not_to match(/v\[0-9\]\*\)/),
                        'the permissive prefix glob must be gone'
    expect(body).to match(/^\s*echo "tag=\$\{TAG\}" >> "\$GITHUB_OUTPUT"$/)
    expect(body).to match(/^\s*echo "version=\$\{TAG#v\}" >> "\$GITHUB_OUTPUT"$/),
                    'version must be derived by shell parameter expansion stripping the leading v'
  end

  it 'sources the dispatch tag via step env before the ref-name fallback (REL-09)' do
    resolve = step_by_id('version')
    mapped = resolve.dig('env', 'DISPATCH_TAG')
    expect(mapped).to eq('${{ inputs.tag }}'),
                      'dispatch input crosses the trigger boundary via step env only'
    body = resolve.fetch('run')
    dispatch_pos = body.index('DISPATCH_TAG')
    ref_pos = body.index('GITHUB_REF_NAME')
    expect(dispatch_pos).not_to be_nil, 'resolve body never consults the dispatch input'
    expect(ref_pos).not_to be_nil
    expect(dispatch_pos).to be < ref_pos,
                            'dispatch wins — under dispatch GITHUB_REF_NAME is the ref (branch), not the tag'
    expect(body.scan('GITHUB_REF_NAME')).to eq(['GITHUB_REF_NAME']),
                                            'ref-name must remain reachable only inside the release fallback branch'
  end

  it 'proves the release exists before anything touches credentials or the tap (dispatch-only, REL-09)' do
    check = run_steps.find { |s| s['run'].include?('gh release view') } or
      raise "#{path} has no gh release view existence check"
    expect(check['if']).to eq("${{ github.event_name == 'workflow_dispatch' }}"),
                           'the existence check is dispatch-only — release events already carry the tag'
    expect(check.dig('env', 'GH_TOKEN')).to eq('${{ github.token }}')
    expect(check.dig('env', 'TAG')).to eq('${{ steps.version.outputs.tag }}')
    expect(check['run']).to match(/^\s*gh release view "\$TAG"/)
    check_pos = steps.index(check)
    guard = run_steps.find { |s| s['run'].include?('TAP_DEPLOY_KEY') } or
      raise "#{path} has no credential guard step — ordering assertion broken"
    tap_checkout = steps.find { |s| s.dig('with', 'repository') == 'phuongddx/homebrew-spm-cache' } or
      raise "#{path} never checks out the tap repository — ordering assertion broken"
    guard_pos = steps.index(guard)
    tap_pos = steps.index(tap_checkout)
    expect(check_pos).to be < guard_pos, 'a nonexistent tag must fail red before credentials are touched'
    expect(check_pos).to be < tap_pos, 'a nonexistent tag must fail red before the tap is touched'
  end

  it 'authenticates the tap push with a write-access deploy key (REL-04 substitute)' do
    expect(steps.map { |s| s['uses'] }.compact).not_to include('actions/create-github-app-token@v3'),
                                                       'the App-token mint is gone — the 2026-08-30 operator pivot replaced it with a deploy key'

    tap_checkout = steps.find { |s| s.dig('with', 'repository') == 'phuongddx/homebrew-spm-cache' } or
      raise "#{path} never checks out the tap repository"
    expect(tap_checkout['uses']).to eq('actions/checkout@v5')
    expect(tap_checkout.dig('with', 'ssh-key')).to eq('${{ secrets.TAP_DEPLOY_KEY }}'),
                                                   'the deploy key must reach git via the checkout ssh-key input'
    expect(tap_checkout.fetch('with')).not_to have_key('token'),
                                              'no token input — auth is the deploy key alone'
    expect(tap_checkout.dig('with', 'path')).to eq('tap')
    checkouts = steps.count { |s| s['uses'] == 'actions/checkout@v5' }
    expect(checkouts).to eq(1), 'exactly one checkout — the unused main-repo checkout is gone'
  end

  it 'never references the retired credential names' do
    expect(text).not_to include('TAP_REPO_TOKEN'),
                        'TAP_REPO_TOKEN is the dead classic PAT this phase retires (REL-04)'
    expect(text).not_to include('TAP_APP_ID'),
                        'TAP_APP_ID belongs to the abandoned App route (operator pivot to deploy key, 2026-08-30)'
    expect(text).not_to include('TAP_APP_PRIVATE_KEY'),
                        'TAP_APP_PRIVATE_KEY belongs to the abandoned App route (operator pivot to deploy key, 2026-08-30)'
  end

  it 'fails loudly naming the deploy-key secret when it is missing (REL-04)' do
    guard = run_steps.find { |s| s['run'].include?('TAP_DEPLOY_KEY') } or
      raise "#{path} has no credential guard step"
    expect(guard.dig('env', 'TAP_DEPLOY_KEY')).to eq('${{ secrets.TAP_DEPLOY_KEY }}'),
                                                  'the secret crosses the boundary via step env only'
    body = guard.fetch('run')
    expect(body).to match(/^\s*if \[ -z "\$TAP_DEPLOY_KEY" \]/)
    expect(body).to match(/^\s*echo "::error::[^\n]*TAP_DEPLOY_KEY/),
                    'the error annotation must NAME the secret (never print values)'
  end

  it 'gates the tarball download on retries, non-emptiness, and gzip magic before hashing (REL-05)' do
    body = step_by_id('sha').fetch('run')
    expect(body).to match(/^\s*curl -fL --retry 3 --retry-delay 2 /),
                    'download must use curl -fL with --retry 3 --retry-delay 2'
    expect(body).to match(/^\s*test -s release\.tar\.gz \|\| /), 'non-empty file gate missing'
    expect(body).to match(/^\s*magic=\$\(od -An -tx1 -N2 release\.tar\.gz/), 'gzip magic-byte read missing'
    magic_pos = body.index(/^\s*\[ "\$magic" = "1f8b" \]/)
    expect(magic_pos).not_to be_nil, 'gzip magic-byte gate (1f8b) missing'
    digest_pos = body.index(/^\s*SHA=\$\(shasum -a 256 /)
    expect(digest_pos).not_to be_nil, 'sha256 digest computation missing'
    expect(magic_pos).to be < digest_pos,
                         'the digest must run strictly AFTER the integrity gate — an error page must never be hashed'
  end

  it 'hashes and pins the same byte source: prefers an attached asset, falls back to the archive loudly (WR-02)' do
    sha = step_by_id('sha')
    expect(sha.dig('env', 'GH_TOKEN')).to eq('${{ github.token }}'),
                                          'asset discovery is authenticated through step env only'
    body = sha.fetch('run')
    expect(body).to match(/^\s*ASSET_URL="\$\(gh release view "\$TAG" .*--json assets /),
                    'asset discovery must list the release assets before choosing a byte source'
    expect(body).to include('endswith(".tar.gz")'),
                    'select tarball assets only — a gem or zip asset must never be hashed'
    expect(body).to match(%r{^\s*TARBALL_URL="https://github\.com/\$\{GITHUB_REPOSITORY\}/archive/refs/tags/\$\{TAG\}\.tar\.gz"}),
                    'the fallback byte source remains the auto-generated tag archive'
    expect(body).to match(/^\s*echo "::warning::/),
                    'the archive fallback must warn loudly — auto-generated bytes are not guaranteed stable'
    expect(body).to match(/^\s*echo "url=\$\{TARBALL_URL\}" >> "\$GITHUB_OUTPUT"$/),
                    'the hashed byte source must become a step output so the formula pins exactly it'
    expect(body.index('gh release view')).to be < body.index(/^\s*curl -fL /),
                                             'byte-source selection must precede the download'
  end

  it 'edits the formula with exactly-one-match anchors and full-line postconditions (REL-07)' do
    edit = run_step_by_marker('replace_exactly_one')
    expect(edit.dig('env', 'TARBALL_URL')).to eq('${{ steps.sha.outputs.url }}'),
                                              'the formula url must be pinned to exactly the byte source the sha step hashed'
    expect(edit.dig('env', 'VERSION')).to be_nil,
                                          'the edit step no longer synthesizes the url from the version'
    body = edit.fetch('run')
    expect(body).to match(/^\s*count=\$\(grep -cE /), 'match-count check via grep -cE missing'
    expect(body).to match(/^\s*if \[ "\$count" -ne 1 \]/),
                    'failure branch must fire on any count other than 1 (0 or >1 both fail red)'
    expect(body).to match(/^\s*sed -i -E /), 'GNU in-place extended-regex sed missing'

    url_re = body.lines.find { |l| l =~ /^\s*URL_RE=/ } or
      raise "#{path} edit step defines no URL_RE"
    expect(url_re).to include('^  url "'),
                      'url pattern anchored to the full line INCLUDING the 2-space formula-class indent (live shape)'
    expect(url_re).to include('archive/refs/tags/')
    expect(url_re).to include('releases/download/'),
                      'the anchor must also match a pinned release-asset url — idempotent re-runs see the asset shape'
    expect(url_re).to include('.tar\.gz"$')

    sha_re = body.lines.find { |l| l =~ /^\s*SHA_RE=/ } or
      raise "#{path} edit step defines no SHA_RE"
    expect(sha_re).to include('^  sha256 "'),
                      'sha256 pattern anchored to the full line INCLUDING the 2-space formula-class indent (live shape)'
    expect(sha_re).to include('[0-9a-f]{64}')
    expect(sha_re).to include('"$')
    expect(body).to match(/replace_exactly_one "\$URL_RE" '  url "/),
                    'the replacement must reproduce the indentation — sed consumes it with the match'
    expect(body).to match(/replace_exactly_one "\$SHA_RE" '  sha256 "/)

    postconditions = body.lines.select { |l| l =~ /^\s*grep -Fqx / }
    expect(postconditions.size).to eq(2),
                                   'expected exactly two full-line postconditions (url, sha256)'
    joined = postconditions.join
    expect(joined).to include('${TARBALL_URL}'),
                      'the url postcondition carries the pinned byte source — the version assertion (no version stanza exists)'
    expect(joined).to include('${SHA256}')

    expect(body).not_to include('version "'),
                        'the live tap formula has no version stanza — a version-field edit is a silent zero-match no-op'
  end

  it 'neuters sed metacharacters before every substitution (WR-01)' do
    body = run_step_by_marker('replace_exactly_one').fetch('run')
    escape = body.lines.find { |l| l.include?("replacement=$(printf '%s' \"$replacement\"") } or
      raise "#{path} never sanitizes the sed replacement — & expands to the whole match and a delimiter char breaks the s expression"
    expect(escape).to include("sed -e 's/[&,\\\\]/\\\\&/g'"),
                      'escape &, backslash, and the s delimiter (,) in the replacement before sed sees it'
    substitution = body.lines.find { |l| l =~ /^\s*sed -i -E / } or
      raise "#{path} lost the GNU in-place extended-regex sed substitution"
    expect(substitution).to include('"s,$pattern,$replacement,"'),
                            'comma-delimited s expression — | cannot be the delimiter once the url anchor carries ERE alternation'
    expect(body.index(escape)).to be < body.index(substitution),
                                  'the sanitized replacement is the one sed consumes'
  end

  it 'publishes loudly: explicit no-diff branch, unguarded push, no suppression (REL-06)' do
    expect(text).not_to include('|| exit 0'),
                        'the double-pipe-exit-zero sequence converts commit/push failures into green runs'
    commit = run_steps.find { |s| s['run'].include?('git diff --cached --quiet') } or
      raise "#{path} commit step has no explicit no-diff detection"
    body = commit.fetch('run')
    expect(body).to match(/^\s*if git diff --cached --quiet; then/)
    expect(body).to match(/^\s*echo "::notice::/),
                    'the already-current branch must succeed via a visible notice annotation'
    expect(body).to match(/^\s*git push\s*$/), 'git push must be bare and unguarded'
  end

  it 'starts every update-tap run body with set -euo pipefail' do
    run_steps.each do |s|
      expect(s['run'].lines.first&.strip).to eq('set -euo pipefail'),
                                             "step '#{s['name']}' must start with set -euo pipefail"
    end
  end

  it 'never expands trigger contexts inside run script bodies' do
    run_steps.each do |s|
      msg = "step '#{s['name']}' expands a trigger context inside the script body " \
            '(injection surface — dynamic values reach the script through env only)'
      expect(s['run']).not_to match(/\$\{\{\s*inputs\./), msg
      expect(s['run']).not_to match(/\$\{\{\s*github\.event\./), msg
    end
  end
end
