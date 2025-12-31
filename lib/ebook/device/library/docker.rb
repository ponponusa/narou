# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

module Device::Library
  module Docker
    def get_device_root_dir(volume_name)
      nil
    end

    def eject(volume_name)
      raise Device::CantEject
    end
  end
end
