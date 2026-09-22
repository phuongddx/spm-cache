# frozen_string_literal: true

require 'spec_helper'
require 'spm_cache/cache/fingerprint'

# rubocop:disable Metrics/BlockLength
RSpec.describe SPMCache::Cache::Fingerprint do
  let(:pin) { { 'identity' => 'alamofire', 'state' => { 'version' => '5.9.1', 'revision' => 'abc123' } } }
  let(:toolchain) { { swift_version: '6.0', xcode_version: 'Xcode 16.0' } }
  let(:config_stub) do
    double('config', run_sdk: 'iphonesimulator', run_config: 'debug',
                     run_merge_slices: true, run_library_evolution: true)
  end
  let(:context) { described_class.context(config: config_stub, toolchain: toolchain) }

  describe '.for' do
    it 'returns 8 hex chars' do
      expect(described_class.for(package: 'Alamofire', pin: pin, context: context))
        .to match(/\A[0-9a-f]{8}\z/)
    end

    it 'is deterministic across key order' do
      a = described_class.for(package: 'Alamofire', pin: pin, context: context)
      b = described_class.for(package: 'Alamofire', pin: pin, context: context.to_a.to_h)
      expect(a).to eq(b)
    end

    it 'changes when the pin changes' do
      bumped = pin.merge('state' => { 'version' => '5.10.0', 'revision' => 'def456' })
      expect(described_class.for(package: 'Alamofire', pin: bumped, context: context))
        .not_to eq(described_class.for(package: 'Alamofire', pin: pin, context: context))
    end

    it 'changes when swift version changes' do
      other = context.merge('swift_version' => '6.1')
      expect(described_class.for(package: 'Alamofire', pin: pin, context: other))
        .not_to eq(described_class.for(package: 'Alamofire', pin: pin, context: context))
    end

    it 'cascades dependency hash changes upstream' do
      deps = { 'Logging' => '11111111' }
      before = described_class.for(package: 'App', pin: pin, dependencies: deps, context: context)
      after = described_class.for(package: 'App', pin: pin,
                                  dependencies: deps.merge('Logging' => '22222222'), context: context)
      expect(before).not_to eq(after)
    end
  end

  describe '.pin_data' do
    it 'normalizes identity/version/branch/revision tolerantly' do
      expect(described_class.pin_data(pin)).to eq(
        'identity' => 'alamofire', 'version' => '5.9.1', 'branch' => nil, 'revision' => 'abc123'
      )
      expect(described_class.pin_data({ 'identity' => 'x' })).to eq(
        'identity' => 'x', 'version' => nil, 'branch' => nil, 'revision' => nil
      )
    end
  end

  describe '.map_for' do
    it 'hashes bottom-up over graph dependencies' do
      graph = [
        { 'module' => 'Logging', 'dependencies' => [] },
        { 'module' => 'Alamofire', 'dependencies' => ['Logging'] }
      ]
      pins = { 'Logging' => { 'identity' => 'swift-log' }, 'Alamofire' => pin }
      map = described_class.map_for(graph_entries: graph, pins: pins,
                                    config: config_stub, toolchain: toolchain)
      direct = described_class.for(package: 'Logging', pin: pins['Logging'], dependencies: {},
                                   context: context)
      expect(map['Logging']).to eq(direct)
      expect(map['Alamofire']).to match(/\A[0-9a-f]{8}\z/)
    end
  end
end
# rubocop:enable Metrics/BlockLength
