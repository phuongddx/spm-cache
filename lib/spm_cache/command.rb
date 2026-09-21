# frozen_string_literal: true

require 'claide'

module SPMCache
  class Command < CLAide::Command
    self.abstract_command = true
    self.command = 'spm-cache'
    self.version = SPMCache::VERSION
    self.description = 'Cache SPM dependencies as xcframeworks.'

    def self.default_subcommand
      'use'
    end

    def self.options
      [
        ['--sdk=SDK', 'SDK to build for (default: iphonesimulator)'],
        ['--config=CONFIG', 'Build configuration (default: debug)'],
        ['--log-dir=DIR', 'Directory for run-log files'],
        ['--no-run-log', 'Disable run-log capture for this invocation'],
        ['--no-merge-slices', 'Disable merging framework slices'],
        ['--no-library-evolution', 'Disable Swift library evolution flags']
      ].concat(super)
    end

    def initialize(argv)
      @sdk = argv.option('sdk')
      @config = argv.option('config')
      @log_dir = argv.option('log-dir')
      @run_log = argv.flag?('run-log', true)
      @merge_slices = argv.flag?('merge-slices', true)
      @library_evolution = argv.flag?('library-evolution', true)
      publish_run_scope!
      super
    end

    def validate!
      super
    end

    def publish_run_scope!
      run_scope = Core::Config.instance
      return unless run_scope.respond_to?(:run_sdk=)

      run_scope.run_sdk = @sdk || Options::SDK
      run_scope.run_config = @config || Options::CONFIG
      run_scope.run_merge_slices = @merge_slices.nil? ? Options::MERGE_SLICES : @merge_slices
      run_scope.run_library_evolution = @library_evolution.nil? ? Options::LIBRARY_EVOLUTION : @library_evolution
    end

    def run
      help!
    end
  end
end
