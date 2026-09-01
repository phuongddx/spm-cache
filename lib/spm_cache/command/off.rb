# frozen_string_literal: true

module SPMCache
  class Command
    class Off < Command
      include BaseOptions

      self.summary = 'Force source mode for specific targets'
      self.description = 'Disables caching for specified targets by adding them to the ignore list.'

      def initialize(argv)
        @targets = argv.arguments!
        super
      end

      def run
        config = Core::Config.instance
        # D-03 (16-01): one source of truth -- the SAME locked,
        # clobber-proof, atomic mutator the web toggle POST uses.
        # The mutator's in-lock load is the only load whose result
        # feeds the write; the published output lines and their
        # order are the contract and stay byte-identical (pinned by
        # spec/command_off_shared_mutator_spec.rb).
        config.set_ignored_all(@targets.to_h { |target| [target, true] })

        puts "Added #{@targets.join(', ')} to ignore list"
        puts "Run 'spm-cache' to use source mode for these targets"
      end
    end
  end
end
