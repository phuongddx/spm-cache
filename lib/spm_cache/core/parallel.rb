# frozen_string_literal: true

require "parallel"

module SPMCache
  module Core
    module ParallelExt
      refine Array do
        def parallel_map(&block)
          Parallel.map(self) { |item| block.call(item) }
        end

        def parallel_each(&block)
          Parallel.each(self) { |item| block.call(item) }
        end
      end
    end
  end
end
