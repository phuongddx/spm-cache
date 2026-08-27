# frozen_string_literal: true

require "fileutils"
require "tempfile"

module SPMCache
  module SPM
    # Seeds a package checkout with the host app's own resolved dependency
    # graph before that checkout is ever inspected (`swift package describe`)
    # or built, so a per-package build resolves the same transitive versions
    # the host app resolved -- not fresh, unbounded-upward ranges from the
    # package's own manifest (FID-02). Pure filesystem: no shell-out, no
    # network, no JSON parsing of the seeded content (D-01: copy verbatim).
    module ResolvedGraph
      RESOLVED_FILENAME = "Package.resolved"

      class << self
        # The one file this run should seed every checkout from, or nil when
        # no host graph is available anywhere (the byte-identical-to-v0.3.0
        # default). The umbrella's own already-resolved `Package.resolved`
        # (written by `swift package resolve`, checkout_resolver.rb:24) wins
        # over `host_graph_path` when both exist -- it is what the checkouts
        # on disk were actually materialized from.
        def source_for(umbrella_dir:, host_graph_path:)
          umbrella_resolved = File.join(umbrella_dir, RESOLVED_FILENAME)
          return umbrella_resolved if File.exist?(umbrella_resolved)
          return host_graph_path if host_graph_path && File.exist?(host_graph_path)

          nil
        end

        # Copies `source_path`'s bytes verbatim into `<pkg_dir>/Package.resolved`
        # via a temp-file-then-rename (atomic on one filesystem). Returns a
        # snapshot of what was there before, so `restore!` can put it back
        # exactly -- distinguishing "nothing existed" from "something did".
        def seed!(source_path, pkg_dir)
          destination = File.join(pkg_dir, RESOLVED_FILENAME)
          snapshot = snapshot_for(destination)
          atomic_write(destination, File.binread(source_path))
          snapshot
        end

        # Undoes `seed!`: removes the seeded file when nothing existed before,
        # or writes the prior content back atomically when something did.
        def restore!(pkg_dir, snapshot)
          destination = File.join(pkg_dir, RESOLVED_FILENAME)
          if snapshot[:existed]
            atomic_write(destination, snapshot[:content])
          else
            FileUtils.rm_f(destination)
          end
        end

        # True when `pkg_dir` carries a committed `.xcodeproj` -- Pitfall 11's
        # vendored-project shape, for which `Package.resolved` is structurally
        # irrelevant (xcodebuild never reads it). Same glob shape as
        # `Buildable#ambiguous_project_checkout?` (build_pipeline.rb), but
        # `.any?` instead of `.length >= 2`: even one vendored `.xcodeproj`
        # already defeats seeding, unlike the multi-project disambiguation
        # problem that only bites at 2+.
        def vendored_xcodeproj?(pkg_dir)
          Dir.glob(File.join(pkg_dir, "*.xcodeproj")).any?
        end

        private

        def snapshot_for(destination)
          File.exist?(destination) ? { existed: true, content: File.binread(destination) } : { existed: false }
        end

        def atomic_write(destination, content)
          tmp = Tempfile.new(["resolved_graph", ".tmp"], File.dirname(destination))
          tmp.binmode
          tmp.write(content)
          tmp.close
          File.rename(tmp.path, destination)
        rescue StandardError
          tmp&.unlink
          raise
        end
      end
    end
  end
end
