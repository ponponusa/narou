# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

module Narou
  module ApiV1
    #
    # API Documentation エンドポイント
    #
    module Documentation
      def self.register(app)
        #
        # Swagger UI表示
        #
        app.get "/api/docs" do
          swagger_ui_path = File.join(settings.public_folder, "swagger-ui", "index.html")
          if File.exist?(swagger_ui_path)
            send_file swagger_ui_path
          else
            halt 404, "Swagger UI not found at #{swagger_ui_path}"
          end
        end

        #
        # OpenAPI仕様書配信
        #
        app.get "/api/openapi.yaml" do
          content_type "application/x-yaml"
          openapi_path = File.join(File.dirname(__FILE__), "../../../docs/openapi.yaml")
          if File.exist?(openapi_path)
            send_file openapi_path
          else
            halt 404, "OpenAPI spec not found at #{openapi_path}"
          end
        end
      end
    end
  end
end
