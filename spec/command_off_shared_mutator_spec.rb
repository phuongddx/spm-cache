# frozen_string_literal: true

require 'spec_helper'
require 'claide'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'yaml'

# 16-01 / D-03: `spm-cache off`'s published contract, pinned by the
# first spec the verb has ever had. Task 1 rerouted its write through
# the shared Config mutator the web toggle POST uses -- these rows are
# the proof that NOTHING observable moved: the two output lines
# byte-for-byte (full-line equality, never a fragment match), the
# de-duplicating ignore-list merge in argv order, the PROBED P2 file
# shape (full default key set, hand-written comments dropped -- D-05's
# honesty sentence describes existing behavior and row 3 is the
# evidence), idempotence, the shared path with the web-side mutator,
# and survival of pre-existing entries and glob patterns. Hermetic:
# a tmpdir project on the Config singleton, restored in ensure; the
# verb is driven through its real constructor with a real argv object
# so arguments! parses the targets exactly as the CLI does.
RSpec.describe SPMCache::Command::Off, 'through the shared mutator (D-03)' do
  let(:project_dir) { Dir.mktmpdir('spm-cache-off') }
  let(:config) { SPMCache::Core::Config.instance }

  around do |example|
    previous_project_dir = config.project_dir
    previous_config_path = config.config_path
    SPMCache::Core::Config.configure(project_dir: project_dir)
    config.reset!
    example.run
  ensure
    config.reset!
    SPMCache::Core::Config.configure(project_dir: previous_project_dir, config_path: previous_config_path)
    FileUtils.rm_rf(project_dir)
  end

  OFF_TEMPLATE = SPMCache::ROOT.join('lib/spm_cache/assets/templates/spm-cache.yml.template').freeze

  def run_off(*targets)
    original = $stdout
    $stdout = StringIO.new
    begin
      described_class.new(CLAide::ARGV.new(targets)).run
      $stdout.string
    ensure
      $stdout = original
    end
  end

  def config_path
    File.join(project_dir, 'spm-cache.yml')
  end

  def disk_ignore
    YAML.safe_load(File.read(config_path))['ignore']
  end

  it 'prints exactly the two established lines, in order, byte-for-byte -- and nothing else' do
    output = run_off('Alamofire')

    expect(output).to eq(
      "Added Alamofire to ignore list\n" \
      "Run 'spm-cache' to use source mode for these targets\n"
    )
  end

  it 'joins multiple targets in argv order on the first line and lands them in the ignore list, de-duplicated, in that order' do
    output = run_off('SnapKit', 'Alamofire', 'SnapKit')

    expect(output).to eq(
      "Added SnapKit, Alamofire, SnapKit to ignore list\n" \
      "Run 'spm-cache' to use source mode for these targets\n"
    )
    expect(disk_ignore).to eq(%w[SnapKit Alamofire])
  end

  it 'rewrites the shipped template into the full default key set with the target ignored, comments gone (PROBED P2 / D-05 evidence)' do
    FileUtils.cp(OFF_TEMPLATE.to_s, config_path)
    expect(File.read(config_path)).to include('# runs_keep: 50') # the seed really is the commented template

    run_off('NewPkg')

    parsed = YAML.safe_load(File.read(config_path))
    expect(parsed.keys).to contain_exactly(*SPMCache::Core::Config::DEFAULT_CONFIG.keys) # the default nine
    expect(parsed['ignore']).to eq(['NewPkg'])
    # The hand-written comments are gone on the first write -- the
    # behavior D-05's honesty sentence describes, now with evidence.
    rewritten = File.read(config_path)
    expect(rewritten).not_to include('# runs_keep: 50')
    expect(rewritten).not_to include('# cache_only: []')
  end

  it 'is idempotent: running the verb twice for the same target leaves exactly one entry' do
    run_off('Alamofire')
    run_off('Alamofire')

    expect(disk_ignore).to eq(['Alamofire'])
  end

  it 'shares the write path with the web side: the entry is the same exact-entry truth, and a web-side removal leaves the rest of the file intact' do
    run_off('Alamofire', 'SnapKit')

    # The exact-entry test the web read model applies to the SAVED
    # list: the entry `off` wrote is visible to the dashboard's own
    # checkbox truth.
    expect(disk_ignore.include?('Alamofire')).to be true

    # The web-side mutation (POST /api/toggle's route body) removes
    # exactly that entry through the SAME mutator; everything else
    # survives -- one source of truth, two callers.
    config.set_ignored('Alamofire', false)

    parsed = YAML.safe_load(File.read(config_path))
    expect(parsed['ignore']).to eq(['SnapKit'])
    expect(parsed.keys).to contain_exactly(*SPMCache::Core::Config::DEFAULT_CONFIG.keys)
  end

  it 'leaves pre-existing entries and glob patterns untouched by the write' do
    File.write(config_path, YAML.dump(
                              SPMCache::Core::Config::DEFAULT_CONFIG.dup.merge(
                                'ignore' => ['Test*', 'MyCompany?', 'ExactName']
                              )
                            ))

    run_off('NewPkg')

    expect(disk_ignore).to eq(['Test*', 'MyCompany?', 'ExactName', 'NewPkg'])
  end
end
