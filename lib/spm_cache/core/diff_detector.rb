# frozen_string_literal: true

require 'json'

module SPMCache
  module Core
    # Detects changes between the current `spm-cache.lock` (snapshot from the
    # last successful run) and the live Xcode project's SPM graph
    # (Package.resolved + project.pbxproj package references). This is the
    # structural moat vs Scipio: spm-cache reads the project directly, so the
    # diff is free -- no separate manifest the user must keep in sync.
    class DiffDetector
      # A structured diff result. `added`/`removed`/`updated` are arrays of
      # package identity strings (lockfile name or URL basename). `updated`
      # entries carry "{name}: {old} -> {new}" for readability.
      Diff = Struct.new(:added, :removed, :updated, keyword_init: true) do
        def empty?
          added.empty? && removed.empty? && updated.empty?
        end

        def total
          added.size + removed.size + updated.size
        end

        # Human-readable summary matching the acceptance criteria:
        #   "Detected: +2 packages (Foo, Bar). Regenerating proxy package."
        #   "No changes detected. Proxy package up to date."
        def summary
          return 'No changes detected. Proxy package up to date.' if empty?

          parts = []
          unless added.empty?
            parts << "+#{added.size} package#{'s' if added.size != 1} (#{added.join(', ')})"
          end
          unless removed.empty?
            parts << "-#{removed.size} package#{'s' if removed.size != 1} (#{removed.join(', ')})"
          end
          parts << "~#{updated.size} updated (#{updated.join(', ')})" unless updated.empty?
          "Detected: #{parts.join(', ')}. Regenerating proxy package."
        end

        def to_s
          summary
        end
      end

      attr_reader :project_path, :lockfile_path

      def initialize(project_path:, lockfile_path:)
        @project_path = project_path
        @lockfile_path = lockfile_path
      end

      # Returns a Diff comparing the live project state against the lockfile.
      # An empty Diff means the proxy package is up to date (fast path).
      def detect
        locked = locked_packages
        live = live_packages

        added = []
        removed = []
        updated = []

        # Packages in live state but not locked -> added
        live.each_key do |key|
          added << label_for(live[key]) unless locked.key?(key)
        end

        # Packages in lockfile but not in live state -> removed
        locked.each_key do |key|
          removed << label_for(locked[key]) unless live.key?(key)
        end

        # Packages in both but version/revision changed -> updated
        live.each do |key, live_pkg|
          locked_pkg = locked[key]
          next unless locked_pkg

          old_ver = locked_pkg['version'] || locked_pkg['revision']
          new_ver = live_pkg['version'] || live_pkg['revision']
          next if old_ver == new_ver

          updated << "#{label_for(live_pkg)}: #{old_ver || '?'} -> #{new_ver || '?'}"
        end

        Diff.new(added: added, removed: removed, updated: updated)
      end

      private

      # Returns { normalized_key => {name, url, version, revision} } for every
      # package in the existing lockfile. The key is the normalized URL (or path
      # for local packages) so identity survives scheme/.git-suffix variations.
      def locked_packages
        result = {}
        return result unless @lockfile_path && File.exist?(@lockfile_path)

        content = File.read(@lockfile_path)
        return result if content.strip.empty?

        data = JSON.parse(content)
        data.each_value do |proj_data|
          (proj_data['packages'] || []).each do |pkg|
            key = identity_key(pkg['repositoryURL'], pkg['path_from_root'] || pkg['path'], pkg['name'])
            result[key] = {
              'name' => pkg['name'],
              'repositoryURL' => pkg['repositoryURL'],
              'path' => pkg['path_from_root'] || pkg['path'],
              'version' => pkg['version'],
              'revision' => pkg['revision']
            }
          end
        end
        result
      end

      # Returns { normalized_key => {name, url, version, revision} } for every
      # package the project currently resolves, sourced from Package.resolved
      # (authoritative for resolved versions) supplemented by project.pbxproj
      # package references (covers local packages / un-resolved refs).
      def live_packages
        result = {}
        File.basename(@project_path)

        # 1. Package.resolved -- authoritative resolved graph
        resolved = find_package_resolved
        if resolved && File.exist?(resolved)
          data = JSON.parse(File.read(resolved))
          (data['pins'] || []).each do |pin|
            url = pin['location']
            state = pin['state'] || {}
            key = identity_key(url, nil, pin['identity'])
            result[key] = {
              'name' => pin['identity'],
              'repositoryURL' => url,
              'path' => nil,
              'version' => state['version'],
              'revision' => state['revision']
            }
          end
        end

        # 2. project.pbxproj SPM refs -- supplement local packages and any refs
        # not yet captured in Package.resolved (e.g. just-added local package).
        merge_project_refs(result)

        result
      end

      def find_package_resolved
        # Xcode stores Package.resolved inside the .xcodeproj bundle (modern
        # Xcode) or at the workspace level. Search recursively.
        Dir.glob(File.join(@project_path, '**/Package.resolved')).find { |f| File.exist?(f) } ||
          Dir.glob(File.join(File.dirname(@project_path), '**', 'Package.resolved')).find { |f| File.exist?(f) }
      end

      def merge_project_refs(result)
        return unless File.exist?(@project_path)

        begin
          require 'xcodeproj'
          project = Xcodeproj::Project.open(@project_path)
        rescue StandardError
          return
        end

        project.root_object.package_references.to_a.each do |ref|
          if ref.respond_to?(:repositoryURL) && ref.repositoryURL
            url = ref.repositoryURL
            key = identity_key(url, nil, nil)
            next if result.key?(key)

            result[key] =
              { 'name' => File.basename(url, '.git'), 'repositoryURL' => url, 'path' => nil, 'version' => nil,
                'revision' => nil }
          else
            path = local_ref_path(ref)
            next unless path
            # Skip the spm-cache proxy ref itself -- it's not a real dependency
            next if path.to_s.include?(File.join('spm-cache', 'packages', 'proxy'))

            key = identity_key(nil, path, nil)
            next if result.key?(key)

            result[key] =
              { 'name' => File.basename(path), 'repositoryURL' => nil, 'path' => path, 'version' => nil,
                'revision' => nil }
          end
        end
      end

      # Deterministic identity key for a package, normalized so that ssh/https
      # URL variants and trailing .git suffixes compare equal. Falls back to
      # the package name or path basename when no URL is available.
      def identity_key(url, path, name)
        if url && !url.empty?
          normalize_url(url)
        elsif path && !path.empty?
          "local:#{File.basename(path)}"
        elsif name
          "name:#{name}"
        else
          'unknown'
        end
      end

      # Reads the relative path from a local SPM package reference, handling
      # both the xcodeproj gem's snake_case accessor and the underlying pbxproj
      # attribute name (relativePath) so the detector works regardless of
      # xcodeproj version.
      def local_ref_path(ref)
        if ref.respond_to?(:relative_path) && ref.relative_path
          ref.relative_path
        elsif ref.respond_to?(:relativePath) && ref.relativePath
          ref.relativePath
        end
      end

      def normalize_url(url)
        stripped = url.to_s.strip.sub(/\.git\z/i, '')
        case stripped
        when /\Agit@([^:]+):(.+)\z/
          "#{Regexp.last_match(1).downcase}/#{Regexp.last_match(2)}"
        when %r{\A(?:ssh|git|https?)://(?:[^@/]+@)?([^/]+)/(.+)\z}
          "#{Regexp.last_match(1).downcase}/#{Regexp.last_match(2)}"
        when %r{\Afile://(.+)\z}
          "local:#{File.basename(Regexp.last_match(1))}"
        else
          stripped.downcase
        end
      end

      def label_for(pkg)
        pkg['name'] || (pkg['repositoryURL'] && File.basename(pkg['repositoryURL'],
                                                              '.git')) || (pkg['path'] && File.basename(pkg['path'])) || 'unknown'
      end
    end
  end
end
