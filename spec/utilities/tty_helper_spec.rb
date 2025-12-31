# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe TTYHelper do
  describe ".non_interactive?" do
    around do |example|
      original = ENV["NAROU_NONINTERACTIVE"]
      begin
        ENV.delete("NAROU_NONINTERACTIVE")
        example.run
      ensure
        if original
          ENV["NAROU_NONINTERACTIVE"] = original
        else
          ENV.delete("NAROU_NONINTERACTIVE")
        end
      end
    end

    it "returns true when the environment forces non-interactive mode" do
      ENV["NAROU_NONINTERACTIVE"] = "1"
      expect(described_class.non_interactive?).to be(true)
    end

    it "returns true when the input does not support TTY operations" do
      non_tty = StringIO.new
      expect(described_class.non_interactive?(non_tty)).to be(true)
    end

    it "returns false when the input is a TTY" do
      fake_tty = instance_double(IO, tty?: true)
      expect(described_class.non_interactive?(fake_tty)).to be(false)
    end

    it "returns true when Narou.web? is true" do
      fake_tty = instance_double(IO, tty?: true)
      allow(Narou).to receive(:web?).and_return(true)
      expect(described_class.non_interactive?(fake_tty)).to be(true)
    end
  end
end
