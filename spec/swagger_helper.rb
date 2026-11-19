require "rails_helper"

RSpec.configure do |config|
  config.openapi_root = Rails.root.join("openapi").to_s

  config.openapi_specs = {
    "v1/openapi.yaml" => {
      openapi: "3.0.3",
      info: {
        title: "Library API",
        version: "v1"
      },
      paths: {},
      servers: [
        { url: "http://localhost:3000" }
      ],
      components: {
        schemas: {
          error: {
            type: :object,
            properties: { error: { type: :string } },
            required: %w[error]
          },
          validation_errors: {
            type: :object,
            properties: {
              errors: {
                type: :object,
                additionalProperties: { type: :array, items: { type: :string } }
              }
            },
            required: %w[errors]
          },
          book: {
            type: :object,
            properties: {
              id: { type: :string, format: :uuid },
              serial_number: { type: :string, pattern: "^[0-9]{6}$" },
              title: { type: :string },
              author: { type: :string },
              created_at: { type: :string, format: :"date-time" }
            },
            required: %w[id serial_number title author created_at]
          }
        },
        securitySchemes: {
          bearer_auth: { type: :http, scheme: :bearer }
        }
      },
      security: [ { bearer_auth: [] } ]
    }
  }

  config.openapi_format = :yaml
end
