# frozen_string_literal: true

require 'json'

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

          under_root = recursive_candidates(project_path).first
          return under_root if under_root
          return nil unless parent_fallback

          recursive_candidates(File.dirname(project_path)).first
        end

        # Strict: propagates JSON::ParserError / TypeError so a caller that
        # must fail loudly on a malformed host graph still does.
        def pins(path)
          JSON.parse(File.read(path)).fetch('pins', [])
        end

        # Tolerant: nil means absent, unreadable, or structurally wrong; [] means
        # readable with zero pins. Callers depend on telling those apart --
        # reading "unreadable" as "empty host graph" would erase the lock.
        def pins_or_nil(path)
          return nil unless path && File.exist?(path)

          data = JSON.parse(File.read(path))
          return nil unless data.is_a?(Hash)

          data['pins'] || []
        rescue JSON::ParserError, TypeError
          nil
        end

        private

        def recursive_candidates(root)
          Dir.glob(File.join(root, '**', 'Package.resolved')).select { |f| File.exist?(f) }
        end
      end
    end
  end
end
