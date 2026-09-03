# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

# WEB-04 predicate matrix (pure units -- no server boot). The allowed
# sets derive ONLY from the bound port: hosts {127.0.0.1:port,
# localhost:port}, origins {http://127.0.0.1:port, http://localhost:port}
# -- never a wildcard (localhost is not a trust boundary, CP13).
RSpec.describe SPMCache::Web::Middleware do
  describe '.allowed_host?' do
    it 'accepts the exact loopback host:port pairs derived from the port' do
      expect(described_class.allowed_host?(host: '127.0.0.1:7915', port: 7915)).to be(true)
      expect(described_class.allowed_host?(host: 'localhost:7915', port: 7915)).to be(true)
    end

    it 'matches the host part case-insensitively' do
      expect(described_class.allowed_host?(host: 'LOCALHOST:7915', port: 7915)).to be(true)
      expect(described_class.allowed_host?(host: 'Localhost:7915', port: 7915)).to be(true)
    end

    it 'requires the port to match exactly' do
      expect(described_class.allowed_host?(host: '127.0.0.1:7916', port: 7915)).to be(false)
      expect(described_class.allowed_host?(host: 'localhost:7914', port: 7915)).to be(false)
    end

    it 'rejects a foreign host (DNS rebinding, T-13-02)' do
      expect(described_class.allowed_host?(host: 'evil.com:7915', port: 7915)).to be(false)
      expect(described_class.allowed_host?(host: 'rebound.example:7915', port: 7915)).to be(false)
    end

    it 'rejects a missing, empty, or port-less Host header' do
      expect(described_class.allowed_host?(host: nil, port: 7915)).to be(false)
      expect(described_class.allowed_host?(host: '', port: 7915)).to be(false)
      expect(described_class.allowed_host?(host: 'localhost', port: 7915)).to be(false)
      expect(described_class.allowed_host?(host: '127.0.0.1:', port: 7915)).to be(false)
    end
  end

  describe '.allowed_origin?' do
    it 'accepts a nil Origin (same-navigation / curl carries no Origin)' do
      expect(described_class.allowed_origin?(origin: nil, port: 7915)).to be(true)
    end

    it 'accepts only the http loopback origins on the bound port' do
      expect(described_class.allowed_origin?(origin: 'http://127.0.0.1:7915', port: 7915)).to be(true)
      expect(described_class.allowed_origin?(origin: 'http://localhost:7915', port: 7915)).to be(true)
    end

    it 'rejects a foreign origin (drive-by CSRF, T-13-01)' do
      expect(described_class.allowed_origin?(origin: 'http://evil.com', port: 7915)).to be(false)
      expect(described_class.allowed_origin?(origin: 'https://evil.com', port: 7915)).to be(false)
    end

    it 'rejects scheme and port mismatches on the loopback itself' do
      expect(described_class.allowed_origin?(origin: 'https://127.0.0.1:7915', port: 7915)).to be(false)
      expect(described_class.allowed_origin?(origin: 'http://localhost:7916', port: 7915)).to be(false)
      expect(described_class.allowed_origin?(origin: 'http://127.0.0.1', port: 7915)).to be(false)
    end

    it 'rejects any null-origin string' do
      expect(described_class.allowed_origin?(origin: 'null', port: 7915)).to be(false)
      expect(described_class.allowed_origin?(origin: 'NULL', port: 7915)).to be(false)
    end
  end

  describe '.valid_token?' do
    let(:token) { SecureRandom.hex(32) }

    it 'accepts the exact expected token' do
      expect(described_class.valid_token?(token: token, expected_token: token)).to be(true)
    end

    it 'rejects a wrong token of the same length' do
      wrong = token.reverse
      expect(described_class.valid_token?(token: wrong, expected_token: token)).to be(false)
    end

    it 'rejects a wrong-length token without short-circuiting on length (T-13-06)' do
      expect(described_class.valid_token?(token: 'short', expected_token: token)).to be(false)
      expect(described_class.valid_token?(token: 'x' * 1_000, expected_token: token)).to be(false)
    end

    it 'rejects an absent token and an absent expected token' do
      expect(described_class.valid_token?(token: nil, expected_token: token)).to be(false)
      expect(described_class.valid_token?(token: token, expected_token: nil)).to be(false)
      expect(described_class.valid_token?(token: nil, expected_token: nil)).to be(false)
    end

    it 'is not defeated by empty-string tokens' do
      expect(described_class.valid_token?(token: '', expected_token: token)).to be(false)
      expect(described_class.valid_token?(token: '', expected_token: '')).to be(false)
    end
  end
end
