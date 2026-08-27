# frozen_string_literal: true

require 'json'

require 'spm_cache/core/config'

module SPMCache
  module Core
    # Single locator and parser for the host project's `Package.resolved`.
    # Every site that needs the host resolved graph resolves it here, so the
    # pin source and the change detector that must agree with it cannot answer
    # with different files.
    class PackageResolved
      CANONICAL_RELATIVE_PATH = File.join('project.xcworkspace', 'xcshareddata', 'swiftpm', 'Package.resolved')

      class << self
        # Returns a path or nil; never raises. `parent_fallback` adds a final
        # tier rooted at the parent directory and is taken only by DiffDetector.
        def locate(project_path, parent_fallback: false)
          return nil unless project_path

          # Field bug (measured 2026-08-27): the reference project carries a
          # git-ignored second `.xcodeproj` bundle holding its own copy of
          # Package.resolved, frozen at 8 pins while Xcode's real graph had
          # moved on to 17. `Dir.glob(...).find` answered with the nested copy
          # because `S` (0x53) sorts before `p` (0x70), so every downstream
          # layer agreed with every other on a graph the project did not have.
          # The canonical path must win by construction, not by byte order.
          canonical = File.join(project_path, CANONICAL_RELATIVE_PATH)
          return canonical if File.exist?(canonical)

          workspace = workspace_candidates(project_path).first
          return workspace if workspace

          under_root = newest(recursive_candidates(project_path, exclude_xcodeproj: true))
          return under_root if under_root
          return nil unless parent_fallback

          # A sibling or parent project's own canonical file legitimately sits
          # under an `.xcodeproj` component relative to this root, so that
          # exclusion cannot apply here -- excluding candidates under
          # `project_path` instead is what keeps the project's own nested stale
          # copy from re-entering through the parent.
          newest(recursive_candidates(File.dirname(project_path), exclude_xcodeproj: false,
                                                                  exclude_under: project_path))
        end

        # Strict: propagates JSON::ParserError / TypeError so a caller that
        # must fail loudly on a malformed host graph still does.
        def pins(path)
          value = JSON.parse(File.read(path)).fetch('pins', [])
          raise TypeError, "Package.resolved 'pins' is not an array (got #{value.class})" unless value.is_a?(Array)

          value
        end

        # Tolerant: nil means absent, unreadable, or structurally wrong; [] means
        # readable with zero pins. Callers depend on telling those apart --
        # reading "unreadable" as "empty host graph" would erase the lock.
        def pins_or_nil(path)
          return nil unless path && File.exist?(path)

          data = JSON.parse(File.read(path))
          return nil unless data.is_a?(Hash)

          value = data['pins'] || []
          return nil unless value.is_a?(Array)

          value.select { |pin| pin.is_a?(Hash) }
        rescue JSON::ParserError, TypeError
          nil
        end

        private

        def workspace_candidates(project_path)
          Dir.glob(File.join(File.dirname(project_path), '*.xcworkspace', 'xcshareddata', 'swiftpm',
                             'Package.resolved')).sort.select { |f| File.exist?(f) }
        end

        def recursive_candidates(root, exclude_xcodeproj:, exclude_under: nil)
          Dir.glob(File.join(root, '**', 'Package.resolved')).select do |candidate|
            next false unless File.exist?(candidate)
            next false if sandboxed?(candidate, root)
            next false if exclude_xcodeproj && nested_xcodeproj?(candidate, root)
            next false if exclude_under && under?(candidate, exclude_under)

            true
          end
        end

        # mtime is only ever a tie-break inside a tier: on a fresh checkout or
        # in CI every file carries the same clone-time stamp, so it cannot carry
        # the preference itself.
        def newest(candidates)
          candidates.max_by { |candidate| File.mtime(candidate) }
        end

        def sandboxed?(candidate, root)
          relative_components(candidate, root).include?(Config::SANDBOX_DIR)
        end

        def nested_xcodeproj?(candidate, root)
          relative_components(candidate, root)[0..-2].any? { |part| part.end_with?('.xcodeproj') }
        end

        def under?(candidate, root)
          root_components = path_components(root)
          path_components(candidate).first(root_components.length) == root_components
        end

        def relative_components(candidate, root)
          path_components(candidate).drop(path_components(root).length)
        end

        def path_components(path)
          path.split(File::SEPARATOR).reject { |part| part.empty? || part == '.' }
        end
      end
    end
  end
end
