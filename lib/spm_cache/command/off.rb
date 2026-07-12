# frozen_string_literal: true

module SPMCache
  class Command
    class Off < Command
      include BaseOptions

      self.summary = "Force source mode for specific targets"
      self.description = "Disables caching for specified targets by adding them to the ignore list."

      def initialize(argv)
        @targets = argv.arguments!
        super
      end

      def run
        config = Core::Config.instance
        config.load

        ignore = config.ignore_list + @targets
        config.raw["ignore"] = ignore.uniq
        config.save

        puts "Added #{@targets.join(', ')} to ignore list"
        puts "Run 'spm-cache' to use source mode for these targets"
      end
    end
  end
end
