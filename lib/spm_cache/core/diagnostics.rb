# frozen_string_literal: true

require 'json'

require 'spm_cache/core/sh'
require 'spm_cache/core/config'
require 'spm_cache/core/system'

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
    end
  end
end
