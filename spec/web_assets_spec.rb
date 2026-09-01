# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require_relative 'support/web_server_boot'

# Web::Assets (T-13-04, path traversal): asset names are validated
# basenames ONLY -- separators, "..", leading dots, and NULs are
# rejected before any filesystem call, and the expanded path must stay
# inside the injected root. Serve-through-server examples reuse the
# Task-1 hermetic boot helper with a tmpdir assets root, proving the
# encoded traversal forms end-to-end.
RSpec.describe SPMCache::Web::Assets do
  let(:tmpdir) { Dir.mktmpdir }
  let(:root) { File.join(tmpdir, 'assets') }

  before do
    FileUtils.mkdir_p(root)
    File.write(File.join(root, 'app.js'), '// dashboard bootstrap')
    File.write(File.join(root, 'index.html'), '<!doctype html><title>spm-cache</title>')
    File.write(File.join(root, 'styles.css'), 'body{margin:0}')
    File.binwrite(File.join(root, 'logo.dat'), [0, 1, 2].pack('C*'))
    File.write(File.join(root, '.hidden'), 'secret')
    FileUtils.mkdir_p(File.join(root, 'sub'))
    File.write(File.join(root, 'sub', 'nested.js'), '// nested')
  end

  after { FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir) }

  def assets
    described_class.new(root: root)
  end

  describe '#resolve' do
    it 'resolves a plain basename to the absolute path inside the root' do
      expect(assets.resolve('app.js')).to eq(File.join(root, 'app.js'))
    end

    it 'keeps every accepted resolution inside the root' do
      expect(File.expand_path(assets.resolve('index.html'))).to start_with(File.expand_path(root))
      expect(File.expand_path(assets.resolve('styles.css'))).to start_with(File.expand_path(root))
    end

    it 'rejects separators, backslash separators, .., leading dots, NUL, and empty names' do
      ['a/b.js', 'sub/nested.js', 'a\\b.js', '..', '../server.rb', 'a..b',
       '.hidden', '.', '', "a\0b"].each do |name|
        expect(assets.resolve(name)).to be_nil, "expected #{name.inspect} to be rejected"
      end
    end

    it 'returns nil for a nonexistent basename' do
      expect(assets.resolve('nope.js')).to be_nil
    end
  end

  describe '#content_type' do
    it 'maps the shipped asset extensions' do
      expect(assets.content_type('app.js')).to eq('application/javascript')
      expect(assets.content_type('index.html')).to eq('text/html')
      expect(assets.content_type('styles.css')).to eq('text/css')
      expect(assets.content_type('logo.dat')).to eq('application/octet-stream')
    end
  end

  describe '#serve' do
    it 'returns the exact bytes with the mapped content type' do
      served = assets.serve('logo.dat')
      expect(served[:body]).to eq([0, 1, 2].pack('C*'))
      expect(served[:content_type]).to eq('application/octet-stream')
    end

    it 'returns nil when resolve rejects the name' do
      expect(assets.serve('../server.rb')).to be_nil
    end
  end

  describe 'served through Web::Server' do
    def with_assets_server(&block)
      WebServerBoot.with_server(project_dir: tmpdir, assets: assets, &block)
    end

    it 'serves a static asset with exact bytes and content type, no token required' do
      with_assets_server do |handle|
        res = WebServerBoot.http_get(handle, '/assets/app.js')
        expect(res.code).to eq('200')
        expect(res.body).to eq('// dashboard bootstrap')
        expect(res['Content-Type']).to eq('application/javascript')
      end
    end

    it 'serves index.html at /?token= once the asset exists' do
      with_assets_server do |handle|
        res = WebServerBoot.http_get(handle, '/?token=anything')
        expect(res.code).to eq('200')
        expect(res.body).to include('spm-cache')
        expect(res['Content-Type']).to eq('text/html')
      end
    end

    it '404s every traversal form, encoded or raw, without escaping the root' do
      with_assets_server do |handle|
        ['/assets/%2e%2e/marker.json', '/assets/..%2Fserver.json',
         '/assets/../server.rb', '/assets/sub/nested.js',
         '/assets/.hidden', '/assets/..'].each do |path|
          res = WebServerBoot.http_get(handle, path)
          expect(res.code).to eq('404'), "expected #{path} to 404"
        end
      end
    end

    it '403s an asset request on a bad Host before any file IO' do
      with_assets_server do |handle|
        res = WebServerBoot.http_get(handle, '/assets/app.js', 'Host' => "evil.com:#{handle.port}")
        expect(res.code).to eq('403')
      end
    end
  end
end
