# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'tmpdir'
require 'spm_cache/cache/fingerprint'

# rubocop:disable Metrics/BlockLength
RSpec.describe SPMCache::Installer::Build, 'module-keyed fingerprint pins' do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'Fake.xcodeproj') }
  let(:pkg_dir) { File.join(tmpdir, 'checkouts', 'Alamofire') }
  let(:context) { { 'sdk' => 'iphonesimulator', 'config' => 'debug', 'toolchain' => 'fixed' } }
  let(:lockfile_data) do
    {
      'Fake.xcodeproj' => {
        'packages' => [
          {
            'name' => 'alamofire',
            'version' => version,
            'products' => [{ 'name' => 'Alamofire', 'type' => 'library', 'targets' => ['Alamofire'] }]
          }
        ]
      }
    }
  end
  let(:version) { '1.0.0' }

  before do
    FileUtils.mkdir_p(project_path)
    FileUtils.mkdir_p(pkg_dir)
    lockfile_path = File.join(tmpdir, 'spm-cache.lock')
    File.write(lockfile_path, JSON.generate(lockfile_data))
    cachemap = SPMCache::Cache::Cachemap.new(
      graph_data: [{ 'module' => 'Alamofire', 'status' => 'missed' }]
    )

    allow_any_instance_of(SPMCache::Installer).to receive(:perform_install).and_wrap_original do |original, *_args|
      receiver = original.receiver
      receiver.instance_variable_set(:@cachemap, cachemap)
      receiver.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))
      nil
    end
    allow_any_instance_of(described_class).to receive(:resolve_umbrella_checkouts).and_return(nil)
    allow_any_instance_of(described_class).to receive(:checkout_map).and_return('Alamofire' => pkg_dir)
    allow(SPMCache::SPM::ResolvedGraph).to receive(:source_for).and_return(nil)
    allow(SPMCache::Cache::Fingerprint).to receive(:context).and_return(context)
    allow(SPMCache::Core::Config.instance).to receive(:default_sdk).and_return('iphonesimulator')
    allow(SPMCache::Core::Config.instance).to receive(:cache_dir).and_return(tmpdir)
  end

  after { FileUtils.remove_entry(tmpdir) }

  def lockfile_path
    File.join(tmpdir, 'spm-cache.lock')
  end

  def make_installer
    described_class.new(project: project_path)
  end

  it 'maps package identities and product names to the same raw pin' do
    lockfile = SPMCache::Core::Lockfile.new(lockfile_path)
    map = make_installer.send(:module_pin_map, lockfile)

    expect(map['Alamofire']).to eq(
      'identity' => 'alamofire',
      'state' => { 'version' => '1.0.0', 'revision' => nil, 'branch' => nil }
    )
    expect(map['alamofire']).to eq(map['Alamofire'])
  end

  it 'passes the product-keyed map into BuildPipeline and changes with pin version' do
    pipeline_runs = []
    allow(SPMCache::SPM::BuildPipeline).to receive(:run) do |**kwargs|
      pipeline_runs << kwargs
      File.join(kwargs[:out_dir], "#{kwargs[:name]}.xcframework")
    end

    make_installer.perform_install
    product_pin = pipeline_runs.first[:pins_override].fetch('Alamofire')
    initial_hash = SPMCache::Cache::Fingerprint.for(
      package: 'Alamofire', pin: product_pin, dependencies: {}, context: context
    )

    lockfile_json = JSON.parse(File.read(lockfile_path))
    lockfile_json['Fake.xcodeproj']['packages'].first['version'] = '2.0.0'
    File.write(lockfile_path, JSON.generate(lockfile_json))
    make_installer.perform_install

    updated_pin = pipeline_runs.last[:pins_override].fetch('Alamofire')
    updated_hash = SPMCache::Cache::Fingerprint.for(
      package: 'Alamofire', pin: updated_pin, dependencies: {}, context: context
    )

    expect(pipeline_runs).to have_attributes(size: 2)
    expect(product_pin['state']['version']).to eq('1.0.0')
    expect(initial_hash).to match(/\A[0-9a-f]{8}\z/)
    expect(updated_pin['state']['version']).to eq('2.0.0')
    expect(updated_hash).not_to eq(initial_hash)
  end
end
# rubocop:enable Metrics/BlockLength
