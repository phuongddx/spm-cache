# frozen_string_literal: true

require 'digest'

module SPMCache
  module Web
    # Pure request predicates backing the Router's security gate (WEB-04).
    # No WEBrick dependency -- every predicate takes plain values, so the
    # unit matrix never boots a server. Allowed sets derive ONLY from the
    # bound port, never a wildcard: localhost is not a trust boundary
    # (research CP13), any page on the internet can reach it.
    class Middleware
      LOOPBACK_HOSTS = %w[127.0.0.1 localhost].freeze

      class << self
        # Host allowlist (DNS-rebinding defense, T-13-02): exact
        # "host:port" pairs on the bound port, host part
        # case-insensitive, port exact. A missing Host is rejected.
        def allowed_host?(host:, port:)
          return false if host.nil?

          host_part, _separator, port_part = host.to_s.rpartition(':')
          return false unless port_part == port.to_s

          LOOPBACK_HOSTS.include?(host_part.downcase)
        end

        # Origin allowlist (drive-by CSRF defense, T-13-01): an absent
        # Origin is allowed (same-navigation / curl carry none); a present
        # Origin must be exactly one of the http loopback origins on the
        # bound port. "null" and https forms never match.
        def allowed_origin?(origin:, port:)
          return true if origin.nil?

          allowed = LOOPBACK_HOSTS.map { |h| "http://#{h}:#{port}" }
          allowed.include?(origin)
        end

        # Per-launch token check (T-13-06 timing side-channel): SHA256-
        # digest BOTH sides -- which equalizes length -- then fold the
        # digests with XOR-accumulate and compare the fold. Never `==` on
        # the raw token, and never short-circuit on the supplied token's
        # length: a wrong-length guess still pays the full compare. Only
        # the expected side (a server-held constant, not attacker input)
        # may early-exit when absent.
        def valid_token?(token:, expected_token:)
          return false if expected_token.to_s.empty?

          fixed_time_equal?(digest(token.to_s), digest(expected_token.to_s))
        end

        private

        def digest(value)
          Digest::SHA256.digest(value)
        end

        # Constant-work equality over two equal-length digest strings:
        # every byte pair is XORed into the accumulator before the single
        # zero check, so the runtime does not depend on where (or whether)
        # a mismatch occurs.
        def fixed_time_equal?(left, right)
          diff = 0
          left.bytes.zip(right.bytes) { |a, b| diff |= a ^ b }
          diff.zero?
        end
      end
    end
  end
end
