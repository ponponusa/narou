# frozen_string_literal: true

require "lib/loading/extension"

RSpec.describe Narou::OpenURIOptions do
  describe ".build" do
    before do
      allow(Inventory).to receive(:load).with("local_setting").and_return(local_setting)
    end

    let(:local_setting) { {} }

    it "uses Firefox-compatible navigation headers by default" do
      options = described_class.build(allow_redirections: :safe)

      expect(options).to include(
        "User-Agent" => a_string_including("Firefox/"),
        "Accept" => a_string_including("text/html"),
        "Accept-Language" => a_string_including("ja"),
        "Accept-Charset" => "utf-8",
        "Connection" => "keep-alive",
        allow_redirections: :safe
      )
      expect(options).not_to have_key("Accept-Encoding")
    end

    it "preserves cookies and an explicitly configured user agent" do
      local_setting["user-agent"] = "Configured Agent"

      options = described_class.build("Cookie" => "over18=off")

      expect(options).to include(
        "User-Agent" => "Configured Agent",
        "Cookie" => "over18=off"
      )
    end
  end
end
