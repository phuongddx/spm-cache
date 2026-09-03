# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SPMCache::Core::Sh do
  describe '.capture_output' do
    it 'runs a simple command and returns output' do
      result = described_class.capture_output('echo hello')
      expect(result).to eq('hello')
    end
  end

  describe '.run' do
    it 'returns hash with output and status' do
      result = described_class.run('echo test')
      expect(result[:output]).to eq("test\n")
      expect(result[:status]).to eq(0)
    end

    it 'raises on command failure' do
      expect { described_class.run('false') }.to raise_error(SPMCache::Core::GeneralError)
    end

    # Field bug: xcodebuild (and most compilers/build tools) write their
    # actual failure reason to STDOUT, not STDERR -- a bare stderr-only
    # error message hid the real cause behind an uninformative "Command
    # failed (exit N): <cmd>" for every such failure, including a specific
    # deployment-target/libarclite error a caller needed to pattern-match
    # against to decide whether to retry.
    it 'includes stdout content in the raised error message, not just stderr' do
      expect { described_class.run("echo 'the real error is here' && false") }
        .to raise_error(SPMCache::Core::GeneralError, /the real error is here/)
    end

    it 'still includes stderr content in the raised error message' do
      expect { described_class.run("echo 'stderr detail' 1>&2 && false") }
        .to raise_error(SPMCache::Core::GeneralError, /stderr detail/)
    end

    # WR-04: functional recovery (Buildable's low-deployment-target retry)
    # pattern-matches the raised error, but failure_detail bounds the
    # MESSAGE to 60 lines per stream -- a diagnostic that scrolls past the
    # tail made the recovery silently stop firing on logged runs. The error
    # must therefore carry the FULL streamed content: the message stays
    # bounded for display, the matchable content is complete.
    it 'attaches the full streamed output to the raised error, beyond the 60-line message tail (WR-04)' do
      expect do
        described_class.run("printf 'is only available in iOS %s.0 or newer\\n' 99; for i in $(seq 1 100); do echo filler $i; done; false")
      end.to raise_error(SPMCache::Core::GeneralError) do |e|
        expect(e.message).not_to include('iOS 99.0') # the message tail alone misses it
        expect(e.full_output).to include('is only available in iOS 99.0 or newer')
      end
    end
  end
end

RSpec.describe SPMCache::Core::UI do
  describe '.info' do
    it 'prints message to stdout' do
      expect { described_class.info('test message') }.to output("test message\n").to_stdout
    end
  end

  describe '.warn' do
    it 'prints warning to stderr' do
      expect { described_class.warn('danger') }.to output("[warn] danger\n").to_stderr
    end
  end
end
