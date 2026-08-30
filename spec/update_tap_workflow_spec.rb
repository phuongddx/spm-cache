# frozen_string_literal: true

require 'spec_helper'

# Structural regression spec for the tap-publish workflow (Phase 11,
# REL-04..09): parse .github/workflows/update-tap.yml with strict Psych and
# pin every release-automation property the phase requires — app-token auth,
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
                                 'the trigger key set is pinned — a pull_request trigger would let fork PRs run the publish path'
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
    expect(jobs.keys.sort).to eq(['update-tap', 'verify-publish'])
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
    expect(install['run']).to match(/^\s*brew install phuongddx\/spm-cache\/spm-cache\b/),
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
                                   'the tap is public and the minted token is auto-revoked at the first job end'
  end

  it 'resolves the tag and version from the release ref via GITHUB_OUTPUT' do
    body = step_by_id('version').fetch('run')
    expect(body).to match(/^\s*TAG="\$GITHUB_REF_NAME"/),
                       'release path: the tag comes from the ref-name ambient variable'
    expect(body).to match(/^\s*case "\$TAG" in/), 'tag shape must be validated with a case statement'
    expect(body).to match(/^\s*v\[0-9\]\*\) ;;/)
    expect(body).to match(/^\s*\*\) echo "::error::/), 'shape failure must emit a red error annotation'
    expect(body).to match(/^\s*echo "tag=\$\{TAG\}" >> "\$GITHUB_OUTPUT"$/)
    expect(body).to match(/^\s*echo "version=\$\{TAG#v\}" >> "\$GITHUB_OUTPUT"$/),
                       'version must be derived by shell parameter expansion stripping the leading v'
  end

  it 'sources the dispatch tag via step env before the ref-name fallback (REL-09)' do
    resolve = step_by_id('version')
    expect(resolve.dig('env', 'DISPATCH_TAG')).to eq('${{ inputs.tag }}'),
              'the dispatch input crosses the trigger-context boundary via step env only — never run-body interpolation'
    body = resolve.fetch('run')
    dispatch_pos = body.index('DISPATCH_TAG')
    ref_pos = body.index('GITHUB_REF_NAME')
    expect(dispatch_pos).not_to be_nil, 'resolve body never consults the dispatch input'
    expect(ref_pos).not_to be_nil
    expect(dispatch_pos).to be < ref_pos,
              'dispatch branch takes precedence — under dispatch GITHUB_REF_NAME is the ref (branch), not the tag'
    expect(body.scan('GITHUB_REF_NAME')).to eq(['GITHUB_REF_NAME']),
              'the ref-name variable must remain reachable only inside the release fallback branch'
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
    mint = steps.find { |s| s['id'] == 'app-token' } or
      raise "#{path} has no app-token step — ordering assertion broken"
    tap_checkout = steps.find { |s| s.dig('with', 'repository') == 'phuongddx/homebrew-spm-cache' } or
      raise "#{path} never checks out the tap repository — ordering assertion broken"
    mint_pos = steps.index(mint)
    tap_pos = steps.index(tap_checkout)
    expect(check_pos).to be < mint_pos, 'a nonexistent tag must fail red before credentials are touched'
    expect(check_pos).to be < tap_pos, 'a nonexistent tag must fail red before the tap is touched'
  end

  it 'mints a scoped GitHub App token and feeds it to the tap checkout (REL-04)' do
    mint = steps.find { |s| s['uses'] == 'actions/create-github-app-token@v3' } or
      raise "#{path} mints no app token — the dead classic-PAT path is still in place"
    expect(mint['id']).to eq('app-token')
    with = mint.fetch('with')
    expect(with['app-id']).to eq('${{ secrets.TAP_APP_ID }}')
    expect(with['private-key']).to eq('${{ secrets.TAP_APP_PRIVATE_KEY }}')
    expect(with['owner']).to eq('phuongddx')
    expect(with['repositories']).to eq('homebrew-spm-cache')

    tap_checkout = steps.find { |s| s.dig('with', 'repository') == 'phuongddx/homebrew-spm-cache' } or
      raise "#{path} never checks out the tap repository"
    expect(tap_checkout['uses']).to eq('actions/checkout@v5')
    expect(tap_checkout.dig('with', 'token')).to eq('${{ steps.app-token.outputs.token }}'),
                                                'the minted token must reach git config via the checkout token input'
    expect(tap_checkout.dig('with', 'path')).to eq('tap')
    expect(steps.count { |s| s['uses'] == 'actions/checkout@v5' }).to eq(1),
           'exactly one checkout — the unused main-repo checkout is gone'
  end

  it 'never references the dead classic-PAT secret' do
    expect(text).not_to include('TAP_REPO_TOKEN'),
                       'TAP_REPO_TOKEN is the dead classic PAT this phase retires (REL-04)'
  end

  it 'fails loudly naming both app secrets when either is missing (REL-04)' do
    guard = run_steps.find { |s| s['run'].include?('TAP_APP_ID') && s['run'].include?('TAP_APP_PRIVATE_KEY') } or
      raise "#{path} has no credential guard step"
    body = guard.fetch('run')
    expect(body).to match(/^\s*if \[ -z "\$TAP_APP_ID" \] \|\| \[ -z "\$TAP_APP_PRIVATE_KEY" \]/)
    expect(body).to match(/^\s*echo "::error::[^\n]*TAP_APP_ID[^\n]*TAP_APP_PRIVATE_KEY/),
                       'the error annotation must NAME both secrets (never print values)'
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

  it 'edits the formula with exactly-one-match anchors and full-line postconditions (REL-07)' do
    body = run_step_by_marker('replace_exactly_one').fetch('run')
    expect(body).to match(/^\s*count=\$\(grep -cE /), 'match-count check via grep -cE missing'
    expect(body).to match(/^\s*if \[ "\$count" -ne 1 \]/),
                       'failure branch must fire on any count other than 1 (0 or >1 both fail red)'
    expect(body).to match(/^\s*sed -i -E /), 'GNU in-place extended-regex sed missing'

    url_re = body.lines.find { |l| l =~ /^\s*URL_RE=/ } or
      raise "#{path} edit step defines no URL_RE"
    expect(url_re).to include('^url "'), 'url pattern must be anchored to the full line'
    expect(url_re).to include('archive/refs/tags/')
    expect(url_re).to include('.tar\.gz"$')

    sha_re = body.lines.find { |l| l =~ /^\s*SHA_RE=/ } or
      raise "#{path} edit step defines no SHA_RE"
    expect(sha_re).to include('^sha256 "'), 'sha256 pattern must be anchored to the full line'
    expect(sha_re).to include('[0-9a-f]{64}')
    expect(sha_re).to include('"$')

    postconditions = body.lines.select { |l| l =~ /^\s*grep -Fqx / }
    expect(postconditions.size).to eq(2),
                                 'expected exactly two full-line postconditions (url, sha256)'
    joined = postconditions.join
    expect(joined).to include('${VERSION}'),
                    'the url postcondition carries the new tag — the version assertion (no version stanza exists)'
    expect(joined).to include('${SHA256}')

    expect(body).not_to include('version "'),
                       'the live tap formula has no version stanza — a version-field edit is a silent zero-match no-op'
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
