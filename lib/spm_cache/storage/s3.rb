# frozen_string_literal: true

require "json"
require "fileutils"
require "spm_cache/storage/base"
require "spm_cache/core/sh"

module SPMCache
  module Storage
    class S3Storage < Base
      attr_reader :uri, :creds_file, :cache_dir

      def initialize(uri:, creds: nil, cache_dir:)
        @uri = uri
        @creds_file = creds ? File.expand_path(creds) : nil
        @cache_dir = cache_dir
      end

      def configured?
        !@uri.nil?
      end

      def pull
        unless configured?
          print_warning("pull")
          return
        end

        validate_awscli!
        env = aws_env
        Sh.run("aws s3 sync #{@uri}/ #{@cache_dir}/ --exact-timestamps", env: env)
        Logger.info("Pulled cache from #{@uri}")
      end

      def push
        unless configured?
          print_warning("push")
          return
        end

        validate_awscli!
        env = aws_env
        Sh.run("aws s3 sync #{@cache_dir}/ #{@uri}/ --delete", env: env)
        Logger.info("Pushed cache to #{@uri}")
      end

      private

      def validate_awscli!
        unless Core::SystemExt::SystemFunctions.which("aws")
          raise Core::GeneralError.new("awscli not found. Install with: pip install awscli")
        end
      end

      def aws_env
        return {} unless @creds_file && File.exist?(@creds_file)

        creds = JSON.parse(File.read(@creds_file))
        {
          "AWS_ACCESS_KEY_ID" => creds["access_key_id"],
          "AWS_SECRET_ACCESS_KEY" => creds["secret_access_key"],
        }
      end
    end
  end
end
