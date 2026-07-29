# frozen_string_literal: true

module Narou
  # Rack access log output that can be enabled at runtime and filters noisy polling requests.
  class FilteredAccessLogger
    POLLING_LOG_PATTERN = %r{"GET /api/v2/(?:system/status|tasks(?:\?[^\s"]*)?)\s+HTTP/}

    attr_writer :enabled

    def initialize(target = $stderr, enabled: false)
      @target = target
      @enabled = enabled
    end

    def enabled?
      @enabled
    end

    def write(message)
      return 0 unless enabled?
      return 0 if message.to_s.match?(POLLING_LOG_PATTERN)

      @target.write(message)
    end

    def <<(message)
      write(message)
      self
    end

    def puts(message)
      return unless enabled?
      return if message.to_s.match?(POLLING_LOG_PATTERN)

      @target.puts(message)
    end

    def flush
      @target.flush if @target.respond_to?(:flush)
    end

    def sync=(value)
      @target.sync = value if @target.respond_to?(:sync=)
    end
  end
end
