# frozen_string_literal: true

module SPMCache
  class Command
    class Remote < Command
      self.abstract_command = true
      def self.default_subcommand; nil; end
      self.summary = "Remote cache commands"
      self.description = "Push or pull the cache to/from a remote storage backend."

      def self.create_storage(config_name = "debug")
        config = Core::Config.instance
        config.load
        remote = config.remote_config(config_name)
        cache_dir = config.cache_dir(config_name)

        return Storage::Base.new unless remote

        if remote["git"]
          Storage::GitStorage.new(remote_url: remote["git"], cache_dir: cache_dir)
        elsif remote["s3"]
          Storage::S3Storage.new(
            uri: remote["s3"]["uri"],
            creds: remote["s3"]["creds"],
            cache_dir: cache_dir,
          )
        else
          Storage::Base.new
        end
      end
    end
  end
end

require "spm_cache/command/remote/pull"
require "spm_cache/command/remote/push"
