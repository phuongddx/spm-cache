# frozen_string_literal: true

module SPMCache
  module Core
    module HashExt
      refine Hash do
        def deep_merge(other, &uniq_block)
          merger = proc do |key, v1, v2|
            if v1.is_a?(Hash) && v2.is_a?(Hash)
              v1.merge(v2, &merger)
            elsif v1.is_a?(Array) && v2.is_a?(Array)
              combined = v1 + v2
              uniq_block ? uniq_block.call(key, combined) : combined.uniq
            else
              v2.nil? ? v1 : v2
            end
          end
          merge(other, &merger)
        end

        def deep_merge!(other, &uniq_block)
          replace(deep_merge(other, &uniq_block))
        end
      end
    end
  end
end
