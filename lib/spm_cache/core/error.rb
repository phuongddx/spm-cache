# frozen_string_literal: true

module SPMCache
  module Core
    class BaseError < StandardError; end

    class GeneralError < BaseError
      attr_reader :exit_status

      def initialize(message = nil, exit_status = 1)
        super(message)
        @exit_status = exit_status
      end
    end
  end
end
