# frozen_string_literal: true

module SPMCache
  module Core
    module UI
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def section(title, &block)
          puts "\n#{'=' * 60}" unless quiet?
          puts title.to_s unless quiet?
          puts "=" * 60 unless quiet?
          yield if block_given?
        end

        def message(msg = "")
          puts msg unless quiet?
        end
        alias_method :info, :message

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

        def quiet?
          @quiet ||= false
        end

        def quiet=(value)
          @quiet = value
        end
      end
    end

    module Log
      include UI
    end
  end
end
