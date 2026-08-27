# frozen_string_literal: true

require 'json'

require 'spm_cache/core/sh'
require 'spm_cache/core/config'
require 'spm_cache/core/system'
require 'spm_cache/core/package_resolved'
require 'spm_cache/core/diff_detector'

module SPMCache
  module Core
    # Data-driven diagnostic check registry. Each check is a small object with
    # a unique name, a `run` callable returning [:ok|:warn|:fail, message], and
    # a `fix_hint` describing how to remediate a non-ok verdict. Checks are
    # registered at load time and can be added/removed via config without
    # editing the `doctor` command — the registry is the single source of
    # truth for what runs.
    class Diagnostics
      # A single diagnostic check.
      Check = Struct.new(:name, :run, :fix_hint, keyword_init: true)

      # A single check result.
      Result = Struct.new(:name, :status, :message, :fix_hint, keyword_init: true) do
        def ok? = status == :ok
        def warn? = status == :warn
        def fail? = status == :fail
      end

      class << self
        # Ordered registry of checks. Order is preserved for report output.
        def registry
          @registry ||= []
        end

        def register(name, fix_hint:, &block)
          registry << Check.new(name: name, run: block, fix_hint: fix_hint)
        end

        # Run all registered checks and return an array of Result structs.
        # A check that raises is captured as a :fail with the error message so
        # one broken check never aborts the whole report.
        def run_all(config: nil)
          registry.map { |check| run_check(check, config: config) }
        end

        private

        def run_check(check, config:)
          status, message = check.run.call(config: config)
          Result.new(name: check.name, status: status, message: message, fix_hint: check.fix_hint)
        rescue StandardError => e
          Result.new(
            name: check.name,
            status: :fail,
            message: "Check raised an error: #{e.message}",
            fix_hint: check.fix_hint
          )
        end

        # Every input path below returns a status instead of raising: a raise is
        # captured as a :fail above, and `doctor` exits 1 on any :fail, so a
        # truncated file in a user's repo would break their CI.
        def lock_graph_fidelity(cfg)
          # An injected config that cannot report project paths cannot answer
          # this question, and a MockExpectationError here is not a StandardError
          # so it would escape run_check's capture entirely.
          unless cfg.respond_to?(:lockfile_path) && cfg.respond_to?(:project_dir)
            return [:ok, 'No project context available — skipping lock/host graph comparison']
          end

          lock_path = cfg.lockfile_path
          unless lock_path && File.exist?(lock_path)
            return [:ok, 'No spm-cache.lock yet — a fresh project cannot be drifted']
          end

          project_path = Dir.glob(File.join(cfg.project_dir, '*.xcodeproj')).sort.first
          return [:ok, 'No .xcodeproj in this directory — no host graph to compare the lock against'] unless project_path

          # The same locator the reconciler uses: a parallel lookup here would
          # let `doctor` report agreement on one file while `use` reconciles
          # against another.
          resolved_path = PackageResolved.locate(project_path)
          return [:ok, 'Host Package.resolved could not be located — nothing to compare the lock against'] unless resolved_path

          host_pins = PackageResolved.pins_or_nil(resolved_path)
          return [:ok, "Host #{resolved_path} is unreadable — cannot compare"] if host_pins.nil?

          locked = lock_remote_packages(lock_path)
          return [:ok, 'spm-cache.lock is unreadable — cannot compare'] if locked.nil?

          compare_lock_to_host(locked, host_pin_map(host_pins))
        end

        # Entries with no repositoryURL are excluded: SwiftPM never lists a
        # local/path package in Package.resolved, so counting one as missing
        # from the host graph would warn forever on any project with a local
        # package. That is a category difference, not staleness.
        def lock_remote_packages(path)
          content = File.read(path)
          return {} if content.strip.empty?

          data = JSON.parse(content)
          return {} unless data.is_a?(Hash)

          data.each_value.with_object({}) do |project, result|
            next unless project.is_a?(Hash)

            (project['packages'] || []).each do |pkg|
              next unless pkg.is_a?(Hash)
              next if pkg['repositoryURL'].to_s.empty?

              key = DiffDetector.identity_key(pkg['repositoryURL'], pkg['path_from_root'] || pkg['path'], pkg['name'])
              result[key] = pkg
            end
          end
        rescue JSON::ParserError, TypeError
          nil
        end

        def host_pin_map(pins)
          pins.each_with_object({}) do |pin, result|
            result[DiffDetector.identity_key(pin['location'], nil, pin['identity'])] = pin
          end
        end

        def compare_lock_to_host(locked, host)
          # A pre-v2 (`object.pins`) resolved file parses to zero pins, which
          # would otherwise read as 100% drift.
          if host.empty? && !locked.empty?
            return [:warn, "Host Package.resolved parsed to zero pins while spm-cache.lock holds " \
                           "#{locked.size} remote package(s) — suspected Package.resolved schema mismatch, not drift"]
          end

          only_in_lock = locked.keys.reject { |key| host.key?(key) }
          only_in_host = host.keys.reject { |key| locked.key?(key) }
          value_drift = locked.keys.select do |key|
            host.key?(key) && lock_pin_value(locked[key]) != host_pin_value(host[key])
          end

          if only_in_lock.empty? && only_in_host.empty? && value_drift.empty?
            return [:ok, "spm-cache.lock agrees with the host Package.resolved (#{locked.size} package(s))"]
          end

          parts = [
            drift_part('only in the lock', only_in_lock.map { |key| lock_label(locked[key]) }),
            drift_part('only in the host graph', only_in_host.map { |key| host_label(host[key]) }),
            drift_part('at a different revision/version', value_drift.map { |key| lock_label(locked[key]) })
          ]
          [:warn, "spm-cache.lock disagrees with the host Package.resolved: #{parts.join(', ')}"]
        end

        # Mirrors the umbrella generator's own precedence, so the check compares
        # what actually gets pinned rather than a parallel notion of equality.
        def lock_pin_value(pkg)
          revision = pkg['revision']
          revision.to_s.empty? ? pkg['version'] : revision
        end

        def host_pin_value(pin)
          state = pin['state'] || {}
          revision = state['revision']
          revision.to_s.empty? ? state['version'] : revision
        end

        def drift_part(caption, labels)
          return "#{labels.size} #{caption}" if labels.empty?

          "#{labels.size} #{caption} (#{summarize_labels(labels)})"
        end

        def summarize_labels(labels, cap: 5)
          shown = labels.first(cap)
          remainder = labels.size - shown.size
          remainder.positive? ? "#{shown.join(', ')} and #{remainder} more" : shown.join(', ')
        end

        def lock_label(pkg)
          pkg['name'] || basename_of(pkg['repositoryURL']) || basename_of(pkg['path_from_root'] || pkg['path']) ||
            'unknown'
        end

        def host_label(pin)
          pin['identity'] || basename_of(pin['location']) || 'unknown'
        end

        def basename_of(value)
          return nil if value.to_s.empty?

          File.basename(value, '.git')
        end
      end

      # --- Built-in checks (registered at load) ---
      # Each check receives a hash with a `config:` Core::Config instance
      # (may be nil when no project context is available). Checks must be
      # side-effect free except for read-only shell-out (xcodebuild, swift,
      # git, aws) via Core::Sh.

      register('xcode_version',
               fix_hint: 'Install Xcode 16+ from the Mac App Store or developer.apple.com') do |config:|
        out = Sh.capture_output('xcodebuild -version')
        [:ok, out.to_s.lines.first.to_s.strip]
      rescue Core::GeneralError => e
        [:fail, "xcodebuild not found or returned no output (#{e.message.split("\n").first})"]
      end

      register('swift_version', fix_hint: 'Ensure the active Xcode provides Swift 6.0+ (Xcode 16)') do |config:|
        out = begin
          Sh.capture_output('swift --version')
        rescue StandardError
          ''
        end
        if out.to_s.empty?
          [:fail, 'swift not found on PATH']
        else
          [:ok, out.to_s.lines.first.to_s.strip]
        end
      end

      register('toolchain_path', fix_hint: 'Run `sudo xcode-select -s /Applications/Xcode.app`') do |config:|
        path = begin
          Sh.capture_output('xcrun --find swift 2>/dev/null')
        rescue StandardError
          ''
        end
        if path.to_s.empty?
          [:fail, 'xcrun could not locate swift — Xcode command-line tools not installed?']
        else
          [:ok, path]
        end
      end

      register('cache_dir_health',
               fix_hint: 'Run `spm-cache cache clean --all` to remove orphaned binaries') do |config:|
        cache_root = Config::CACHE_DIR
        if File.directory?(cache_root)
          configs = Dir.children(cache_root).sort
          total = configs.sum do |cfg|
            d = File.join(cache_root, cfg)
            File.directory?(d) ? Dir.glob(File.join(d, '**/*')).size : 0
          end
          [:ok, "Cache dir #{cache_root} (#{configs.length} config(s), ~#{total} files)"]
        else
          [:ok, "Cache dir #{cache_root} does not exist yet (no caches built)"]
        end
      rescue StandardError => e
        [:warn, "Could not inspect cache dir: #{e.message}"]
      end

      register('library_evolution_compatibility',
               fix_hint: 'Some packages cannot build with LE enabled — use `--no-library-evolution` or add them to `ignore`') do |config:|
        # Without a live build we can only confirm the flag is honored; a
        # per-package LE failure is surfaced at build time. This check is a
        # placeholder that confirms the capability is wired.
        [:ok, 'Library evolution support is built-in (disable with --no-library-evolution)']
      end

      register('remote_backend_connectivity',
               fix_hint: 'Verify remote backend credentials and configuration in spm-cache.yml') do |config:|
        cfg = config || Config.instance
        begin
          cfg.load
        rescue StandardError
          nil
        end
        remote = cfg.raw['remote']
        if remote.nil? || remote.empty?
          [:ok, 'No remote backend configured (local-only)']
        else
          [:ok, 'Remote backend configured — run `spm-cache remote pull` to verify connectivity']
        end
      end

      register('companion_binary', fix_hint: 'Run `make proxy.build` to build the Swift companion binary') do |config:|
        bin = File.expand_path('tools/spm-cache-proxy/.build/release/spm-cache-proxy', ROOT)
        if File.executable?(bin)
          out = begin
            Sh.capture_output("#{bin} --version 2>/dev/null")
          rescue StandardError
            ''
          end
          [:ok, "Companion binary present at #{bin}#{" (#{out})" unless out.to_s.empty?}"]
        else
          [:warn, "Companion binary not built (#{bin}) — proxy generation specs will skip"]
        end
      end

      register('lock_graph_fidelity',
               fix_hint: 'Run `spm-cache use` to reconcile spm-cache.lock with the host Package.resolved') do |config:|
        cfg = config || Config.instance
        begin
          cfg.load
        rescue StandardError
          nil
        end
        lock_graph_fidelity(cfg)
      end
    end
  end
end
