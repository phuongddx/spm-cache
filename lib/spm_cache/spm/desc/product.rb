# frozen_string_literal: true

module SPMCache
  module SPM
    module Desc
      class Product
        attr_reader :name, :pkg_dir, :raw

        def initialize(name: nil, raw: {}, pkg_dir:)
          @raw = raw
          @name = name || raw["name"]
          @pkg_dir = pkg_dir
        end

        def target_names
          raw["targets"] || []
        end

        def targets
          @targets ||= target_names
        end

        def type
          raw["type"]
        end

        def to_h
          { name: @name, targets: target_names, type: type }.compact
        end
      end
    end
  end
end
