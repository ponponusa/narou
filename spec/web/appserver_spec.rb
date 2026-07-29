# frozen_string_literal: true

require "lib/web/appserver"

RSpec.describe Narou::AppServer do
  describe "access log" do
    let(:output) { StringIO.new }
    let(:access_logger) { Narou::FilteredAccessLogger.new(output) }

    after do
      Narou::AppServer.configure_access_log(false)
    end

    it "is disabled together with server banners by default" do
      expect(described_class.settings.access_logger).not_to be_enabled
      expect(described_class.settings.quiet).to be(true)
      expect(described_class.settings.server_settings).to eq(Silent: true)
    end

    it "can be enabled together with server banners" do
      described_class.configure_access_log(true)

      expect(described_class.settings.access_logger).to be_enabled
      expect(described_class.settings.quiet).to be(false)
      expect(described_class.settings.server_settings).to eq(Silent: false)
    end

    it "does not leak the polling pattern constant into AppServer" do
      expect(described_class.const_defined?(:POLLING_LOG_PATTERN, false)).to be(false)
    end

    describe Narou::FilteredAccessLogger do
      before do
        access_logger.enabled = true
      end

      it "filters out GET /api/v2/system/status requests" do
        access_logger.write('127.0.0.1 - - [25/Jul/2026] "GET /api/v2/system/status HTTP/1.1" 200 100')
        expect(output.string).to be_empty
      end

      it "filters out GET /api/v2/tasks list requests with or without query params" do
        access_logger.write('127.0.0.1 - - [25/Jul/2026] "GET /api/v2/tasks HTTP/1.1" 200 100')
        access_logger.write('127.0.0.1 - - [25/Jul/2026] "GET /api/v2/tasks?_=123 HTTP/1.1" 200 100')
        expect(output.string).to be_empty
      end

      it "does not filter out POST /api/v2/tasks/:id/cancel or GET /api/v2/tasks/:id requests" do
        cancel_log = '127.0.0.1 - - [25/Jul/2026] "POST /api/v2/tasks/1/cancel HTTP/1.1" 200 50'
        detail_log = '127.0.0.1 - - [25/Jul/2026] "GET /api/v2/tasks/1 HTTP/1.1" 200 50'

        access_logger.write(cancel_log)
        access_logger.write(detail_log)

        expect(output.string).to include(cancel_log)
        expect(output.string).to include(detail_log)
      end

      it "does not filter out other routes or error responses" do
        error_log = '127.0.0.1 - - [25/Jul/2026] "GET /api/v2/novels HTTP/1.1" 500 200'

        access_logger.write(error_log)

        expect(output.string).to include(error_log)
      end

      it "suppresses all access logs while disabled" do
        access_logger.enabled = false

        access_logger.write('127.0.0.1 - - [25/Jul/2026] "GET /assets/app.js HTTP/1.1" 200 100')

        expect(output.string).to be_empty
      end
    end
  end
end
