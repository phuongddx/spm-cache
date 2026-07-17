# frozen_string_literal: true

require "json"

require "spm_cache/core/syntax/json"
require "spm_cache/core/log"
require "spm_cache/core/error"

module SPMCache
  module Core
    class Lockfile
      include Syntax::JSONRepresentable

      class Pkg
        attr_reader :name, :url, :path, :version, :branch, :revision, :raw, :products

        def initialize(data)
          @raw = data
          if data["repositoryURL"] || data["url"]
            @url = data["repositoryURL"] || data["url"]
            @name = data["name"] || File.basename(@url, ".git")
          elsif data["path_from_root"] || data["path"]
            @path = data["path_from_root"] || data["path"]
            @name = data["name"] || File.basename(@path)
          end
          @version = data["version"]
          @branch = data["branch"]
          @revision = data["revision"]
          @products = data["products"] || []
        end

        def local?
          !@path.nil?
        end

        def remote?
          !@url.nil?
        end

        def slug
          @name&.c99extidentifier
        end

        def to_h
          result = {}
          result["repositoryURL"] = @url if @url
          result["path_from_root"] = @path if @path
          result["name"] = @name if @name
          result["version"] = @version if @version
          result["branch"] = @branch if @branch
          result["revision"] = @revision if @revision
          result["products"] = @products unless @products.empty?
          result
        end
      end

      attr_reader :projects

      def initialize(path = nil)
        @path = path
        @raw = {}
        @projects = {}
        load(path) if path && File.exist?(path)
      end

      def load(path = nil)
        @path = path if path
        return @raw = {} unless @path && File.exist?(@path)

        content = File.read(@path)
        @raw = content.strip.empty? ? {} : JSON.parse(content)
        @projects = @raw
        @raw
      end

      def save(path = nil)
        @path = path if path
        return unless @path

        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, JSON.pretty_generate(@raw))
      end

      def deep_merge!(other_data, &uniq_block)
        merger = proc do |key, v1, v2|
          if v1.is_a?(Hash) && v2.is_a?(Hash)
            v1.merge(v2, &merger)
          elsif v1.is_a?(Array) && v2.is_a?(Array)
            combined = v1 + v2
            uniq_block ? uniq_block.call(key, combined) : combined.uniq
          else
            v2.nil? ? v1 : v2
          end
        end
        @raw = @raw.merge(other_data, &merger)
        @projects = @raw
        self
      end

      def verify!(project_name = nil)
        unknown = unknown_dependencies(project_name)
        return if unknown.empty?

        msg = "Unknown product dependencies detected:\n"
        unknown.each { |dep| msg += "  - #{dep}\n" }
        msg += "\nPlease ensure all packages are properly added to the Xcode project."
        Core::UI.error!(msg)
      end

      def unknown_dependencies(project_name = nil)
        projects_to_check = project_name ? { project_name => @raw[project_name] } : @raw
        unknown = []
        projects_to_check.each do |proj, data|
          next unless data && data["dependencies"]

          all_products = (data["packages"] || []).map do |pkg|
            name = pkg["name"] || File.basename(pkg["repositoryURL"] || pkg["path_from_root"] || "", ".git")
            name
          end

          data["dependencies"].each do |target, deps|
            deps.each do |dep|
              pkg_name = dep.to_s.split("/").first
              unless all_products.include?(pkg_name)
                unknown << "#{proj}: #{target} -> #{dep}"
              end
            end
          end
        end
        unknown
      end

      def pkgs_for_project(project_name)
        data = @raw[project_name] || {}
        (data["packages"] || []).map { |pkg_data| Pkg.new(pkg_data) }
      end

      def dependencies_for_target(project_name, target_name)
        data = @raw[project_name] || {}
        deps = data["dependencies"] || {}
        deps[target_name] || []
      end

      def platforms_for_project(project_name)
        data = @raw[project_name] || {}
        data["platforms"] || {}
      end

      def empty?
        @raw.empty? || @raw.all? { |_, v| v.nil? || v.empty? }
      end
    end
  end
end
