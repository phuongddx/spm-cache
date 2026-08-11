# frozen_string_literal: true

require 'json'
require 'optparse'

require 'spm_cache/command'
require 'spm_cache/core/diagnostics'
require 'spm_cache/core/config'

module SPMCache
  class Command
    class Doctor < Command
      self.summary = 'Run environment diagnostics'
      self.description = 'Checks the Xcode/Swift toolchain, cache-dir health, remote-backend config, and the Swift companion binary. Prints a green/yellow/red report. Use --json for machine-readable output (CI).'

      def self.options
        [['--json', 'Emit diagnostics as JSON instead of a color-coded report']].concat(super)
      end

      def initialize(argv)
        super
        @json = argv.flag?('json', false)
      end

      def run
        require 'spm_cache/core/diagnostics'
        config = Core::Config.instance
        begin
          config.load
        rescue StandardError
          nil
        end
        results = Core::Diagnostics.run_all(config: config)

        if @json
          print_json(results)
        else
          print_report(results)
        end

        # Non-zero exit if any check failed, so CI can gate on it.
        exit 1 if results.any?(&:fail?)
      end

      private

      def print_report(results)
        results.each { |r| puts format_line(r) }
        puts
        ok = results.count(&:ok?)
        warn = results.count(&:warn?)
        fail = results.count(&:fail?)
        puts "Summary: #{ok} ok, #{warn} warning#{'s' if warn != 1}, #{fail} failure#{'s' if fail != 1}"
      end

      def format_line(result)
        marker = case result.status
                 when :ok then '✓'
                 when :warn then '!'
                 when :fail then '✗'
                 end
        line = "#{marker} #{result.name}: #{result.message}"
        line += "\n    ↳ #{result.fix_hint}" unless result.ok? || result.fix_hint.to_s.empty?
        line
      end

      def print_json(results)
        payload = {
          checks: results.map do |r|
            { name: r.name, status: r.status.to_s, message: r.message, fix_hint: r.fix_hint }
          end,
          summary: {
            ok: results.count(&:ok?),
            warnings: results.count(&:warn?),
            failures: results.count(&:fail?)
          }
        }
        puts JSON.pretty_generate(payload)
      end
    end
  end
end
