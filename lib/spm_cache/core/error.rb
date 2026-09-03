# frozen_string_literal: true

module SPMCache
  module Core
    class BaseError < StandardError; end

    class GeneralError < BaseError
      attr_reader :exit_status

      # The FULL streamed command output that produced this failure
      # (WR-04). The #message stays bounded (failure_detail's 60-line tail
      # per stream) for display; callers that pattern-match the error to
      # decide on functional recovery (e.g. Buildable's
      # low-deployment-target retry) must match THIS, since the diagnostic
      # can scroll past the tail on large builds. nil when unavailable.
      attr_accessor :full_output

      def initialize(message = nil, exit_status = 1)
        super(message)
        @exit_status = exit_status
      end
    end
  end
end
