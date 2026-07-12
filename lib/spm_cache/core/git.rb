# frozen_string_literal: true

module SPMCache
  module Core
    class Git
      attr_reader :dir

      def initialize(dir = ".")
        @dir = dir
      end

      def init
        Sh.run("git init", cwd: dir)
      end

      def checkout(branch, opts = {})
        cmd = "git checkout"
        cmd += " -b" if opts[:new]
        cmd += " #{branch}"
        Sh.run(cmd, cwd: dir)
      end

      def fetch(remote = "origin", branch = nil, opts = {})
        cmd = "git fetch"
        cmd += " --depth 1" if opts[:shallow]
        cmd += " #{remote}"
        cmd += " #{branch}" if branch
        Sh.run(cmd, cwd: dir)
      end

      def push(remote = "origin", branch = "main", opts = {})
        cmd = "git push"
        cmd += " --force" if opts[:force]
        cmd += " #{remote} #{branch}"
        Sh.run(cmd, cwd: dir)
      end

      def clean(opts = {})
        cmd = "git clean"
        cmd += " -fd" if opts[:force]
        cmd += " -x" if opts[:x]
        Sh.run(cmd, cwd: dir)
      end

      def add(*paths)
        Sh.run("git add #{paths.join(' ')}", cwd: dir)
      end

      def commit(message)
        Sh.run("git commit -m #{message.inspect}", cwd: dir)
      end

      def remote(name = nil)
        if name
          Sh.capture_output("git remote get-url #{name}", cwd: dir)
        else
          Sh.capture_output("git remote", cwd: dir).split("\n")
        end
      end

      def add_remote(name, url)
        Sh.run("git remote add #{name} #{url}", cwd: dir)
      end

      def set_remote_url(name, url)
        Sh.run("git remote set-url #{name} #{url}", cwd: dir)
      end

      def ensure_remote(name, url)
        if remote.include?(name)
          set_remote_url(name, url)
        else
          add_remote(name, url)
        end
      end

      def status
        Sh.capture_output("git status --porcelain", cwd: dir)
      end

      def branch
        Sh.capture_output("git rev-parse --abbrev-ref HEAD", cwd: dir)
      end

      def has_remote?(name = "origin")
        remote.include?(name)
      end

      def self.git?(dir)
        File.directory?(File.join(dir, ".git"))
      end
    end
  end
end
