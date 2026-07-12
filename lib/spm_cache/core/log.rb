# frozen_string_literal: true

module SPMCache
  module Core
    module UI
      module ClassMethods
        def section(title, &block)
          puts "\n#{'=' * 60}"
          puts title.to_s
          puts "=" * 60
          yield if block_given?
        end

        def info(msg = "")
          puts msg
        end
        alias_method :message, :info

        def warn(msg)
          $stderr.puts "[warn] #{msg}"
        end

        def error(msg)
          $stderr.puts "[error] #{msg}"
        end

        def error!(msg)
          error(msg)
          raise GeneralError.new(msg)
        end
      end

      # Make methods available as module methods (Core::UI.info, etc.)
      extend ClassMethods

      def self.included(base)
        base.extend(ClassMethods)
      end
    end

    module Log
      include UI
    end
  end
end
