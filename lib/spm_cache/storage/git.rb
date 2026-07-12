# frozen_string_literal: true

require "fileutils"
require "spm_cache/storage/base"
require "spm_cache/core/git"
require "spm_cache/core/sh"

module SPMCache
  module Storage
    class GitStorage < Base
      attr_reader :remote_url, :branch, :cache_dir

      def initialize(remote_url:, branch: "main", cache_dir:)
        @remote_url = remote_url
        @branch = branch
        @cache_dir = cache_dir
      end

      def configured?
        !@remote_url.nil?
      end

      def pull
        unless configured?
          print_warning("pull")
          return
        end

        git = Core::Git.new(@cache_dir)
        unless Core::Git.git?(@cache_dir)
          git.init
          git.ensure_remote("origin", @remote_url)
        end

        git.fetch("origin", @branch, shallow: true)
        git.checkout("FETCH_HEAD")
        git.clean(force: true)
        Core::UI.info("Pulled cache from #{@remote_url}/#{@branch}")
      end

      def push
        unless configured?
          print_warning("push")
          return
        end

        git = Core::Git.new(@cache_dir)
        unless Core::Git.git?(@cache_dir)
          git.init
          git.ensure_remote("origin", @remote_url)
        end

        git.add(".")
        begin
          git.commit("Update cache")
        rescue Core::GeneralError
          Core::UI.info("No changes to push")
        end
        git.push("origin", @branch)
        Core::UI.info("Pushed cache to #{@remote_url}/#{@branch}")
      end
    end
  end
end
