# frozen_string_literal: true

module SPMCache
  module Web
    # Traversal-safe static asset resolver (T-13-04): the asset name
    # arriving from the (already percent-decoded by WEBrick) request
    # path must be a plain basename -- separators, backslashes, "..",
    # leading dots, and NULs are rejected BEFORE any filesystem call,
    # and the expanded path must stay inside the injected root
    # (defense-in-depth: a valid basename can never escape anyway).
    # Assets ship inside the gem and carry zero project data, which is
    # why the router serves them without a token check (13-CONTEXT
    # "Token & Security Middleware"); the Host/Origin gate still
    # applies to every asset request.
    class Assets
      # lib/spm_cache/web/assets/ — Plan 13-03 fills index.html, app.js,
      # styles.css, and the vendored cytoscape.min.js; the gemspec
      # lib/**/* glob already ships them.
      DEFAULT_ROOT = File.expand_path('../web/assets', __dir__)

      CONTENT_TYPES = {
        '.html' => 'text/html',
        '.css' => 'text/css',
        '.js' => 'application/javascript',
        '.mjs' => 'application/javascript',
        '.json' => 'application/json',
        '.svg' => 'image/svg+xml',
        '.png' => 'image/png'
      }.freeze

      def initialize(root: DEFAULT_ROOT)
        @root = File.expand_path(root)
      end

      # Absolute path inside the root, or nil for any suspicious or
      # nonexistent name.
      def resolve(name)
        return nil unless valid_name?(name)

        path = File.expand_path(name, @root)
        return nil unless path.start_with?("#{@root}/")
        return nil unless File.file?(path)

        path
      end

      def content_type(name)
        CONTENT_TYPES[File.extname(name.to_s).downcase] || 'application/octet-stream'
      end

      # {body:, content_type:} or nil -- the Router maps nil to 404.
      def serve(name)
        path = resolve(name)
        return nil unless path

        { body: File.binread(path), content_type: content_type(name) }
      end

      private

      def valid_name?(name)
        name.is_a?(String) &&
          !name.empty? &&
          !name.start_with?('.') &&
          !name.include?('/') &&
          !name.include?('\\') &&
          !name.include?('..') &&
          !name.include?("\0")
      end
    end
  end
end
