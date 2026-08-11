# frozen_string_literal: true

require 'fileutils'

require 'spm_cache/command'
require 'spm_cache/core/config'
require 'spm_cache/core/lockfile'
require 'spm_cache/core/sh'

module SPMCache
  class Command
    class Init < Command
      self.summary = 'Bootstrap a project for spm-cache'
      self.description = 'Detects the Xcode project, prompts for platforms/config/remote-backend, and generates spm-cache.yml + a seeded spm-cache.lock so the first `spm-cache use` is a fast path. Non-interactive via flags.'

      def self.options
        [
          ['--project=PATH', 'Path to the .xcodeproj (default: auto-detect in cwd)'],
          ['--platform=LIST', 'Comma-separated platforms (ios,macos,watchos,tvos)'],
          ['--default-config=CONFIG', 'Default build config (debug/release)'],
          ['--remote=BACKEND', 'Remote backend (none/git/s3)'],
          ['--remote-url=URL', 'Git remote URL or S3 URI'],
          ['--branch=BRANCH', 'Git remote branch (default: main)'],
          ['--creds=PATH', 'S3 credentials JSON file path']
        ].concat(super)
      end

      def initialize(argv)
        super
        @project = argv.option('project')
        @platforms = argv.option('platform')
        @default_config = argv.option('default-config')
        @remote = argv.option('remote')
        @remote_url = argv.option('remote-url')
        @branch = argv.option('branch') || 'main'
        @creds = argv.option('creds')
      end

      def run
        project_path = resolve_project
        unless project_path
          raise Core::GeneralError,
                'No .xcodeproj found — pass --project or run inside an Xcode project directory'
        end

        Core::UI.info "Bootstrapping spm-cache for #{File.basename(project_path)}..."

        platforms = resolve_platforms
        cfg = resolve_default_config
        remote_hash = resolve_remote

        write_config(project_path, platforms, cfg, remote_hash)
        seed_lockfile(project_path)
        ensure_gitignore(project_path)

        Core::UI.info "Created #{Core::Config::CONFIG_FILENAME} and #{Core::Config::LOCKFILE_FILENAME}."
        Core::UI.info 'Next: run `spm-cache build <target>` then `spm-cache`.'
      end

      private

      def resolve_project
        return @project if @project && File.directory?(@project)

        Dir.glob(File.join(Dir.pwd, '*.xcodeproj')).find { |p| File.directory?(p) }
      end

      def resolve_platforms
        if @platforms
          @platforms.split(',').map(&:strip).reject(&:empty?)
        elsif interactive?
          print 'Platforms (comma-separated: ios,macos,watchos,tvos) [ios]: '
          ($stdin.gets&.chomp || 'ios').split(',').map(&:strip).reject(&:empty?)
        else
          ['ios']
        end
      end

      def resolve_default_config
        if @default_config
          @default_config
        elsif interactive?
          print 'Default build config (debug/release) [debug]: '
          ($stdin.gets&.chomp || 'debug').strip
        else
          'debug'
        end
      end

      def resolve_remote
        backend = @remote || (interactive? ? prompt_remote : 'none')
        return {} if backend.nil? || backend == 'none' || backend.empty?

        url = @remote_url || (interactive? ? prompt('Remote URL: ') : nil)
        return {} if url.nil? || url.empty?

        case backend
        when 'git'
          { 'git' => url, 'branch' => @branch }
        when 's3'
          { 's3' => { 'uri' => url, 'creds' => @creds } }
        else
          {}
        end
      end

      def prompt_remote
        print 'Remote backend (none/git/s3) [none]: '
        ($stdin.gets&.chomp || 'none').strip.downcase
      end

      def prompt(message)
        print message
        $stdin.gets&.chomp&.strip
      end

      # Interactive only when STDIN is a TTY AND no non-interactive flags were
      # supplied. In CI (piped STDIN) or when flags are present, use defaults.
      def interactive?
        $stdin.tty? && @platforms.nil? && @remote.nil?
      end

      # Idempotent diff-merge: load any existing config, merge new values over
      # DEFAULT_CONFIG (preserving user keys), and write back. Never overwrite
      # user-set keys with defaults.
      def write_config(project_path, platforms, cfg, remote_hash)
        config = Core::Config.instance
        config.project_dir = File.dirname(project_path)
        config.config_path = File.join(config.project_dir, Core::Config::CONFIG_FILENAME)
        begin
          config.load
        rescue StandardError
          nil
        end

        config.raw['platforms'] = platforms unless platforms.empty?
        config.raw['default_config'] = cfg if cfg
        config.raw['default_sdk'] = 'iphonesimulator' unless config.raw.key?('default_sdk')
        config.raw['remote'] = remote_hash unless remote_hash.empty?

        config.save
      end

      def seed_lockfile(project_path)
        resolved = find_package_resolved(project_path)
        lockfile_path = File.join(File.dirname(project_path), Core::Config::LOCKFILE_FILENAME)

        if resolved && File.exist?(resolved)
          # Seed from Package.resolved so the first `use` can take the fast path.
          FileUtils.cp(resolved, lockfile_path)
          Core::UI.info "Seeded #{Core::Config::LOCKFILE_FILENAME} from #{resolved}."
        else
          # No resolved graph yet — write an empty lockfile skeleton.
          File.write(lockfile_path, "{\"projects\":[]}\n")
          Core::UI.info "Created empty #{Core::Config::LOCKFILE_FILENAME} (run `spm-cache use` after resolving deps)."
        end
      end

      def find_package_resolved(project_path)
        Dir.glob(File.join(project_path, '**/Package.resolved')).find { |f| File.exist?(f) }
      end

      def ensure_gitignore(project_path)
        gitignore = File.join(File.dirname(project_path), '.gitignore')
        entry = 'spm-cache/'
        lines = File.exist?(gitignore) ? File.readlines(gitignore).map(&:chomp) : []
        return if lines.include?(entry)

        File.open(gitignore, 'a') do |f|
          f.puts unless lines.empty? || lines.last&.end_with?("\n")
          f.puts '# spm-cache sandbox'
          f.puts entry
        end
      end
    end
  end
end
