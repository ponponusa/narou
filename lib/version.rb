# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

module Narou
  VERSION = "2.0.0"
  COMMIT = File.read(File.expand_path("../commitversion", __dir__)).strip.freeze
end
