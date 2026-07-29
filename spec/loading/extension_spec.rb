# frozen_string_literal: true

require "lib/loading/extension"

RSpec.describe Narou::OpenURIOptions do
  describe ".build" do
    before do
      allow(Inventory).to receive(:load).with("local_setting").and_return(local_setting)
    end

    let(:local_setting) { {} }

    it "uses a Firefox-compatible user agent by default" do
      options = described_class.build(allow_redirections: :safe)

      expect(options).to include(
        "User-Agent" => a_string_including("Firefox/"),
        allow_redirections: :safe
      )
      expect(options).not_to include(
        "Accept" => anything,
        "Accept-Charset" => anything,
        "Connection" => anything
      )
    end

    it "adds modern browser headers only for HTML navigation requests" do
      options = make_open_uri_navigation_options(allow_redirections: :safe)

      expect(options).to include(
        "Accept" => a_string_including("text/html"),
        "Upgrade-Insecure-Requests" => "1",
        "Sec-Fetch-Dest" => "document",
        "Sec-Fetch-Mode" => "navigate",
        "Sec-Fetch-Site" => "none",
        "Sec-Fetch-User" => "?1"
      )
      expect(options).not_to have_key("Accept-Charset")
      expect(options).not_to have_key("Connection")
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
