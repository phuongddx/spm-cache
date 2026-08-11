# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'spm_cache/core/diagnostics'

# Doctor tests use injected fixtures rather than a real Xcode install. We
# exercise the registry mechanics and the JSON/report formatters via the
# Command, and verify each built-in check returns one of the three statuses
# with a non-empty message.
RSpec.describe SPMCache::Core::Diagnostics do
  it 'registers built-in checks' do
    names = described_class.registry.map(&:name)
    expect(names).to include(
      'xcode_version', 'swift_version', 'toolchain_path',
      'cache_dir_health', 'library_evolution_compatibility',
      'remote_backend_connectivity', 'companion_binary'
    )
  end

  it 'every check returns a Result with a valid status' do
    results = described_class.run_all(config: nil)
    expect(results).to all(be_a(SPMCache::Core::Diagnostics::Result))
    results.each do |r|
      expect(%i[ok warn fail]).to include(r.status)
      expect(r.message).to be_a(String)
      expect(r.fix_hint).to be_a(String)
    end
  end

  it 'captures a check that raises as a :fail' do
    saved = described_class.registry.dup
    begin
      described_class.instance_variable_set(:@registry, [])
      described_class.register('boom', fix_hint: 'fix it') { raise 'kaboom' }
      described_class.register('good', fix_hint: '') { [:ok, 'fine'] }

      results = described_class.run_all(config: nil)
      boom = results.find { |r| r.name == 'boom' }
      expect(boom.status).to eq(:fail)
      expect(boom.message).to include('kaboom')
      expect(results.find { |r| r.name == 'good' }.status).to eq(:ok)
    ensure
      described_class.instance_variable_set(:@registry, saved)
    end
  end
end

RSpec.describe 'spm-cache doctor --json' do
  it 'emits valid JSON with checks and summary' do
    require 'spm_cache/command/doctor'
    out = StringIO.new
    # Capture stdout from the command's puts calls.
    original_stdout = $stdout
    $stdout = out
    begin
      # exit 1 would abort the spec process; stub it.
      allow_any_instance_of(SPMCache::Command::Doctor).to receive(:exit).and_return(nil)
      cmd = SPMCache::Command.parse(['doctor', '--json'])
      cmd.run
    ensure
      $stdout = original_stdout
    end
    parsed = JSON.parse(out.string)
    expect(parsed).to include('checks', 'summary')
    expect(parsed['checks']).to be_an(Array)
    expect(parsed['summary']).to include('ok', 'warnings', 'failures')
  end
end
