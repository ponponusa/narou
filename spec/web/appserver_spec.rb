# frozen_string_literal: true

require "lib/web/appserver"

RSpec.describe Narou::AppServer do
  describe "log_filter" do
    let(:output) { StringIO.new }
    let(:log_filter) { described_class.middleware.find { |m| m.first == Rack::CommonLogger }&.dig(1, 0) }

    it "is defined on AppServer Rack middleware stack" do
      expect(log_filter).not_to be_nil
    end

    describe "filtering behavior" do
      let(:filter_instance) { log_filter.class.new(output) }

      it "filters out GET /api/v2/system/status requests" do
        filter_instance.write('127.0.0.1 - - [25/Jul/2026] "GET /api/v2/system/status HTTP/1.1" 200 100')
        expect(output.string).to be_empty
      end

      it "filters out GET /api/v2/tasks list requests with or without query params" do
        filter_instance.write('127.0.0.1 - - [25/Jul/2026] "GET /api/v2/tasks HTTP/1.1" 200 100')
        filter_instance.write('127.0.0.1 - - [25/Jul/2026] "GET /api/v2/tasks?_=123 HTTP/1.1" 200 100')
        expect(output.string).to be_empty
      end

      it "does not filter out POST /api/v2/tasks/:id/cancel or GET /api/v2/tasks/:id requests" do
        cancel_log = '127.0.0.1 - - [25/Jul/2026] "POST /api/v2/tasks/1/cancel HTTP/1.1" 200 50'
        detail_log = '127.0.0.1 - - [25/Jul/2026] "GET /api/v2/tasks/1 HTTP/1.1" 200 50'

        filter_instance.write(cancel_log)
        filter_instance.write(detail_log)

        expect(output.string).to include(cancel_log)
        expect(output.string).to include(detail_log)
      end

      it "does not filter out other routes or error responses" do
        error_log = '127.0.0.1 - - [25/Jul/2026] "GET /api/v2/novels HTTP/1.1" 500 200'

        filter_instance.write(error_log)

        expect(output.string).to include(error_log)
      end
    end
  end
end
