# frozen_string_literal: true

require 'spec_helper'

# Guards the REL-08 CLI half: `spm-cache --version` must print the gem version
# to stdout and exit 0. Field bug being guarded: CLAide's Command.parse routes
# a bare `--version` through the default `use` subcommand (default_subcommand
# routing), whose option set rejects the root-only flag -- without the
# intercept in Main.run the flag exits 1 with an unknown-option banner.
RSpec.describe SPMCache::Main do
  describe '.run' do
    it 'prints the gem version to stdout for --version' do
      expect { described_class.run(['--version']) }.to output("#{SPMCache::VERSION}\n").to_stdout
    end

    it 'prints the VERSION file contents (single source of truth)' do
      expected = "#{File.read('VERSION').strip}\n"
      expect { described_class.run(['--version']) }.to output(expected).to_stdout
    end
  end
end
