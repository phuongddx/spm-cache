# frozen_string_literal: true

require 'spec_helper'

# Wave 0 local proofs for the composite Action (04-VALIDATION): parse
# action/action.yml with strict Psych and cross-reference every shell-out
# flag against the gem command file that defines it. The init slice is taken
# from `def self.options` through `.concat(super)` so ONLY init.rb's own
# options count — the inherited base `--config` (command.rb:19) lives outside
# the slice, which is what makes the F1 cross-reference load-bearing
# (CLAide silently accepts inherited flags a subcommand never reads).
RSpec.describe 'action/action.yml' do
  let(:action) { YAML.safe_load_file('action/action.yml', permitted_classes: [], aliases: false) }
  let(:steps) { action.dig('runs', 'steps') }
  let(:run_steps) { steps.select { |s| s.key?('run') } }
  let(:init_step) { run_steps.find { |s| s['run'].include?('spm-cache init') } }
  let(:remote_step) { run_steps.find { |s| s['run'].include?('spm-cache remote') } }

  # Slice each command file's OWN options block: from `def self.options` up to
  # (not including) `.concat(super)`. Super-appended inherited flags are
  # deliberately excluded from the defined set. A missing marker raises naming
  # the file instead of silently degrading the slice (WR-01/WR-04).
  def own_option_flags(path)
    src = File.read(path)
    start_idx = src.index('def self.options') or
      raise "#{path} defines no own options block — update the cross-reference source list"
    concat_idx = src.index('.concat(super)', start_idx) or
      raise "#{path} composes options without .concat(super) — slice boundary broken"
    src[start_idx...concat_idx].scan(/\[(?:['"]{1,2})?\s*--([a-z0-9-]+)(?:=|['"\s])/).flatten.uniq
  end

  let(:init_defined_flags) { own_option_flags('lib/spm_cache/command/init.rb') }
  let(:remote_defined_flags) do
    %w[pull push].flat_map { |sub| own_option_flags("lib/spm_cache/command/remote/#{sub}.rb") }.uniq
  end

  # Core of a description cell: backticks, parenthetical qualifiers, and a
  # leading "Label: " prefix are formatting variance between the two files,
  # not meaning drift (IN-01).
  def description_core(text)
    text.gsub('`', '').split('(').first.strip.split(': ').last.strip.downcase
  end

  let(:readme_rows) do
    section = File.read('action/README.md')[/## Inputs\n(.*?)\n## /m, 1] or
      raise 'action/README.md "## Inputs" section lacks a terminating "## " heading — parity slice broken'
    section.scan(/^\| `([^`]+)` \| (.*?) \| (yes|no) \| (.*?) \|$/).map do |name, desc, required, default|
      { 'name' => name, 'description' => desc, 'required' => required == 'yes', 'default' => default.strip }
    end
  end

  it 'parses as strict YAML and satisfies composite schema rules' do
    expect(action).to be_a(Hash)
    expect(action['name']).to be_a(String)
    expect(action['name']).not_to be_empty
    expect(action['description']).to be_a(String)
    expect(action['description']).not_to be_empty
    expect(action.dig('runs', 'using')).to eq('composite')
    expect(steps.size).to eq(4)
    run_steps.each { |s| expect(s).to include('shell'), "step '#{s['name']}' has run but no shell" }
  end

  it 'declares the accepted input surface with per-input metadata' do
    inputs = action.fetch('inputs')
    expect(inputs.keys.sort).to eq(%w[backend backend-url branch command config creds].sort)
    inputs.each_value do |meta|
      expect(meta['description']).to be_a(String), 'every input needs a description'
      expect(meta['description']).not_to be_empty
    end
    expect(inputs['command']['default']).to eq('pull')
    expect(inputs['backend']['default']).to eq('git')
    expect(inputs['branch']['default']).to eq('main')
    expect(inputs['config']['default']).to eq('debug')
    expect(inputs['creds']['default']).to eq('')
  end

  it 'never expands GitHub input contexts inside run script bodies' do
    run_steps.each do |s|
      msg = "step '#{s['name']}' expands an inputs context inside the script body " \
            '(injection surface, RESEARCH Pattern 1)'
      expect(s['run']).not_to match(/\$\{\{\s*inputs\./), msg
    end
  end

  it 'routes every declared input through step env assignments' do
    referenced = steps.flat_map { |s| (s['env'] || {}).values }
                      .map { |v| v.to_s[/\$\{\{ inputs\.(\S+) \}\}/, 1] }
                      .compact.uniq.sort
    expect(referenced).to eq(action.fetch('inputs').keys.sort)
  end

  it "init step emits only flags the gem's init command defines" do
    emitted = init_step['run'].scan(/--([a-z0-9-]+)(?:=|\s|["'])/).flatten.uniq
    undefined = emitted - init_defined_flags
    msg = 'init step emits flags init.rb\'s own options do not define: ' \
          "#{undefined.join(', ')} (RESEARCH F1 — inherited base flags are " \
          'silently accepted by CLAide and never read by init)'
    expect(undefined).to be_empty, msg
  end

  it 'remote step emits only flags remote pull/push define and composes sync in-action' do
    emitted = remote_step['run'].scan(/--([a-z0-9-]+)(?:=|\s|["'])/).flatten.uniq
    expect(emitted - remote_defined_flags).to be_empty
    expect(remote_step['run']).to include('remote pull --config=')
    expect(remote_step['run']).to include('remote push --config=')
    expect(remote_step['run']).not_to include('remote sync')
    expect(Dir.glob('lib/spm_cache/command/remote/*.rb').map { |f| File.basename(f) }.sort)
      .to eq(['pull.rb', 'push.rb'])
  end

  it 'pins a quoted ruby version satisfying the gemspec' do
    setup_step = steps.find { |s| s['uses']&.start_with?('ruby/setup-ruby') } or
      raise 'action.yml: no ruby/setup-ruby step found — cannot pin ruby-version'
    ruby_version = setup_step.dig('with', 'ruby-version')
    expect(ruby_version).to be_a(String), 'ruby-version must be a quoted string, not a YAML float (Pitfall 4)'
    expect(ruby_version).to eq('3.2')
    gemspec = File.read('spm_cache.gemspec')
    expect(gemspec).to include('>= 3.1.0')
    expect(Gem::Version.new(ruby_version)).to be >= Gem::Version.new('3.1.0')
  end

  it 'installs and invokes the executable the gemspec ships' do
    all_run = run_steps.map { |s| s['run'] }.join("\n")
    expect(all_run).to include('gem install spm-cache --no-document')

    executables = File.read('spm_cache.gemspec')[/spec\.executables\s*=\s*\[([^\]]*)\]/, 1]
                      .scan(/"([^"]+)"/).flatten
    expect(executables).to eq(['spm-cache'])
    expect(all_run.scan(/gem install (\S+)/).flatten.uniq).to eq(executables)
    expect(all_run).not_to match(/gem (?:exec|update|uninstall)\b/)
    invocation = /(?:^|\s)(#{Regexp.escape(executables.first)})(?:\s|$)/
    expect(all_run.scan(invocation).flatten.uniq).to eq(executables)
  end

  it 'README input table matches the action inputs' do
    inputs = action.fetch('inputs')
    expect(readme_rows.map { |r| r['name'] }.sort).to eq(inputs.keys.sort)
    readme_rows.each do |row|
      input = inputs.fetch(row['name'])
      expect(row['required']).to eq(input['required']), "required mismatch for #{row['name']}"
      expected_default = input['default'].nil? || input['default'] == '' ? '—' : "`#{input['default']}`"
      expect(row['default']).to eq(expected_default), "default mismatch for #{row['name']}"
      expect(description_core(row['description'])).to eq(description_core(input['description'])),
              "description mismatch for #{row['name']}"
    end
  end
end
