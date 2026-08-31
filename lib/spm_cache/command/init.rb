# frozen_string_literal: true

require 'json'

require 'spm_cache/command'
require 'spm_cache/core/config'
require 'spm_cache/core/lockfile'
require 'spm_cache/core/package_resolved'

module SPMCache
  class Command
    class Init < Command
      self.summary = 'Bootstrap a project for spm-cache'
      self.description = 'Detects the Xcode project, prompts for platforms/config/remote-backend, and generates spm-cache.yml + a seeded spm-cache.lock so subsequent `spm-cache use` runs can take the fast path. Non-interactive via flags.'

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

        # Write the CANONICAL lockfile shape (mirrors installer.rb's
        # generate_lockfile_from_resolved field-for-field) so the seeded lock
        # is consumable by Core::DiffDetector and lock continuity holds across
        # subsequent `use` runs. init never opens the project via the xcodeproj
        # gem (pure file I/O), so platforms seeds as the empty Hash — the
        # consumer default (core/lockfile.rb platforms_for_project).
        # A malformed or non-object Package.resolved must not abort init
        # mid-run (spm-cache.yml is already written by this point, but the
        # .gitignore entry is not): treat it as absent and seed the empty
        # skeleton, mirroring write_config's rescue posture for corrupt yml.
        pins = []
        seeded = false
        pins, seeded = read_resolved_pins(resolved) if resolved && File.exist?(resolved)
        lockfile_data = {
          File.basename(project_path) => {
            'packages' => pins.map do |pin|
              {
                'repositoryURL' => pin['location'],
                'name' => pin['identity'],
                'version' => pin.dig('state', 'version'),
                'revision' => pin.dig('state', 'revision')
              }
            end,
            'dependencies' => {},
            'platforms' => {}
          }
        }
        File.write(lockfile_path, JSON.pretty_generate(lockfile_data))

        if seeded
          Core::UI.info "Seeded #{Core::Config::LOCKFILE_FILENAME} from #{resolved}."
        else
          Core::UI.info "Created empty #{Core::Config::LOCKFILE_FILENAME} (run `spm-cache use` after resolving deps)."
        end
      end

      # WR-05: a valid-JSON Package.resolved with non-object pins entries
      # ("pins": ["Alamofire"]) used to raise in the pins mapping, aborting
      # init AFTER the yml was written but BEFORE the lockfile and
      # .gitignore -- exactly the mid-run abort the guard above promises
      # never happens. Malformed entries are dropped with a warning instead;
      # the seed stays partial-but-consumable. Returns [pins, seeded].
      def read_resolved_pins(resolved)
        data = JSON.parse(File.read(resolved))
        return [[], false] unless data.is_a?(Hash)

        unless data['pins'].is_a?(Array)
          Core::UI.warn "Package.resolved at #{resolved} has no pins array; seeding an empty lock."
          return [[], true]
        end

        raw_pins = data['pins']
        pins = raw_pins.select { |entry| entry.is_a?(Hash) }
        dropped = raw_pins.length - pins.length
        Core::UI.warn "Package.resolved at #{resolved} dropped #{dropped} malformed pin(s)." if dropped.positive?
        [pins, true]
      rescue JSON::ParserError, TypeError
        Core::UI.warn "Package.resolved at #{resolved} is unreadable; seeding an empty lock."
        [[], false]
      end

      def find_package_resolved(project_path)
        Core::PackageResolved.locate(project_path)
      end

      # Append-once gitignore entries, one per concern (the existing shape):
      # 'spm-cache/' for the build sandbox, '.spm-cache/' for run logs
      # (D-02 — run logs live outside the sandbox and never enter VCS,
      # T-12-05). Each entry is independently idempotent.
      def ensure_gitignore(project_path)
        gitignore = File.join(File.dirname(project_path), '.gitignore')
        append_gitignore_entry(gitignore, 'spm-cache/', '# spm-cache sandbox')
        append_gitignore_entry(gitignore, '.spm-cache/', '# spm-cache run logs')
      end

      def append_gitignore_entry(gitignore, entry, comment)
        lines = File.exist?(gitignore) ? File.readlines(gitignore).map(&:chomp) : []
        return if lines.include?(entry)

        File.open(gitignore, 'a') do |f|
          f.puts unless lines.empty?
          f.puts comment
          f.puts entry
        end
      end
    end
  end
end
