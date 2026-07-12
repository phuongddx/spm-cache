# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "digest"
require "pathname"

module SPMCache
  module Core
    module SystemExt
      refine String do
        def c99extidentifier
          gsub(/[^a-zA-Z0-9_]/, "_")
        end
      end

      refine Pathname do
        def symlink_to(target)
          target = Pathname.new(target) unless target.is_a?(Pathname)
          if exist? || symlink?
            delete
          end
          FileUtils.mkdir_p(parent) unless parent.exist?
          File.symlink(target.expand_path, to_s)
        end

        def copy(dest)
          dest = Pathname.new(dest) unless dest.is_a?(Pathname)
          if directory?
            FileUtils.cp_r(to_s, dest.to_s)
          else
            FileUtils.mkdir_p(dest.parent.to_s)
            FileUtils.cp(to_s, dest.to_s)
          end
        end

        def checksum
          raise "Path does not exist: #{self}" unless exist?
          if directory?
            entries = children.sort_by(&:to_s)
            entries.map(&:checksum).join
          else
            Digest::SHA256.file(to_s).hexdigest
          end
        end
      end

      module SystemFunctions
        def self.which(cmd)
          exts = ENV["PATHEXT"] ? ENV["PATHEXT"].split(";") : [""]
          ENV["PATH"].split(File::PATH_SEPARATOR).each do |path|
            exts.each do |ext|
              exe = File.join(path, "#{cmd}#{ext}")
              return exe if File.executable?(exe) && File.file?(exe)
            end
          end
          nil
        end

        def self.create_tmpdir(prefix = "spm-cache-")
          Dir.mktmpdir(prefix)
        end

        def self.prepare_dir(path)
          FileUtils.mkdir_p(path)
          path
        end

        def self.git?(dir)
          File.directory?(File.join(dir.to_s, ".git"))
        end
      end
    end
  end
end
