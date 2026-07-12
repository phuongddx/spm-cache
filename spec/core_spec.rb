# frozen_string_literal: true

require "spec_helper"

RSpec.describe SPMCache::Core::Sh do
  describe ".capture_output" do
    it "runs a simple command and returns output" do
      result = described_class.capture_output("echo hello")
      expect(result).to eq("hello")
    end
  end

  describe ".run" do
    it "returns hash with output and status" do
      result = described_class.run("echo test")
      expect(result[:output]).to eq("test\n")
      expect(result[:status]).to eq(0)
    end

    it "raises on command failure" do
      expect { described_class.run("false") }.to raise_error(SPMCache::Core::GeneralError)
    end
  end
end

RSpec.describe SPMCache::Core::UI do
  describe ".info" do
    it "prints message to stdout" do
      expect { described_class.info("test message") }.to output("test message\n").to_stdout
    end
  end

  describe ".warn" do
    it "prints warning to stderr" do
      expect { described_class.warn("danger") }.to output("[warn] danger\n").to_stderr
    end
  end
end
