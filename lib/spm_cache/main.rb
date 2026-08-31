# frozen_string_literal: true

require 'pathname'
require 'spm_cache'

module SPMCache
  module Main
    def self.run(argv)
      # Ensure all lib files are loaded
      SPMCache::Main.load_all
      # --version intercept stays FIRST and unlogged (documented discretion:
      # a version query never reaches Command.run, so it is not a run to log).
      return puts(SPMCache::VERSION) if argv.first == '--version' # before default_subcommand routing

      # The tee must install BEFORE CLAide parses argv, so the run-log flags
      # are pre-scanned raw (Pitfall 1) exactly like the --version intercept
      # above. The CLAide-level declarations stay: without them CLAide
      # rejects the argv before the tee installs.
      scan = Core::RunLog.pre_scan(argv)
      run_log = nil
      unless scan.suppressed? || scan.main_log_skipped? # D-03 / SC3 web / D-09 watch
        run_log = Core::RunLog.open(
          runs_dir: scan.log_dir || Core::Config.instance.runs_dir, # D-01 override, D-02 default
          command: scan.verb,
          argv: argv,
          trigger: 'terminal'
        )
      end

      old_out = $stdout
      old_err = $stderr
      status = 0
      begin
        $stdout = run_log.tee_out(old_out) if run_log
        $stderr = run_log.tee_err(old_err) if run_log
        Command.run(argv)
      rescue SystemExit => e # doctor-style explicit exit; CLAide Help
        status = e.status
        raise
      rescue Interrupt # probed: Ruby's top-level Interrupt handling exits 130
        status = 130
        raise
      rescue StandardError => e # GeneralError carries exit_status (default 1)
        status = e.respond_to?(:exit_status) && e.exit_status ? e.exit_status : 1
        # Bare raise everywhere: re-raise $! untouched so today's stderr dump
        # and exit code are preserved bit-for-bit (Pitfall 2 -- never exit
        # from a rescue/ensure).
        raise
      ensure
        $stdout = old_out
        $stderr = old_err # restore streams BEFORE finishing the log
        run_log&.finish(status)
      end
    end

    def self.load_all
      lib_dir = File.expand_path(__dir__)
      # Load all .rb files recursively (sorted for deterministic order)
      Dir.glob("#{lib_dir}/**/*.rb").sort.each do |f|
        require f
      end
    end
  end
end

# Auto-require on load
SPMCache::Main.load_all
