# frozen_string_literal: true

module SPMCache
  module Core
    module Cacheable
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def cacheable(*method_names)
          method_names.each do |method_name|
            original_method = instance_method(method_name)

            define_method(method_name) do |*args, **kwargs, &block|
              @_cache ||= {}
              cache_key = [method_name, args, kwargs]

              if @_cache.key?(cache_key)
                @_cache[cache_key]
              else
                @_cache[cache_key] = original_method.bind_call(self, *args, **kwargs, &block)
              end
            end
          end
        end

        def cacheable_class_method(*method_names)
          method_names.each do |method_name|
            original_method = method(method_name)

            define_singleton_method(method_name) do |*args, **kwargs, &block|
              @class_cache ||= {}
              cache_key = [method_name, args, kwargs]

              if @class_cache.key?(cache_key)
                @class_cache[cache_key]
              else
                @class_cache[cache_key] = original_method.call(*args, **kwargs, &block)
              end
            end
          end
        end
      end

      def invalidate_cache!
        @_cache = {}
      end
    end
  end
end
