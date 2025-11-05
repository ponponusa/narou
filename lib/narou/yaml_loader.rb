# frozen_string_literal: true

require "yaml"
require "date"
require "time"

module Narou
  module YAMLLoader
    class Error < StandardError; end

    PERMITTED_CLASSES = [Date, Time, DateTime].freeze
    PERMITTED_SYMBOLS = [].freeze

    module_function

    def load_file(path)
      load(File.read(path), filename: path)
    end

    def load(content, filename: nil)
      YAML.safe_load(
        content,
        permitted_classes: PERMITTED_CLASSES,
        permitted_symbols: PERMITTED_SYMBOLS,
        aliases: true
      )
    rescue Psych::DisallowedClass, Psych::SyntaxError => e
      raise Error, build_message("YAMLの読み込みに失敗しました", filename, e)
    end

    def build_message(base, filename, exception)
      message = base.dup
      message << " (#{filename})" if filename
      message << ": #{exception.message}"
      message
    end
    private_class_method :build_message
  end
end
