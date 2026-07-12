# frozen_string_literal: true

require "erb"

module SPMCache
  module Utils
    class Template
      TEMPLATES_DIR = SPMCache::LIBEXEC.join("assets", "templates")

      attr_reader :name, :vars

      def initialize(name, vars = {})
        @name = name
        @vars = vars
      end

      def render
        template_path = TEMPLATES_DIR.join("#{name}.template")
        raise "Template not found: #{template_path}" unless template_path.exist?

        content = template_path.read
        ERB.new(content, trim_mode: "-").result(binding)
      end

      def render_to(output_path)
        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, render)
      end

      def self.render(name, vars = {})
        new(name, vars).render
      end

      def self.render_to(name, output_path, vars = {})
        new(name, vars).render_to(output_path)
      end
    end
  end
end
