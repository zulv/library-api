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
              status: { type: :string, enum: %w[available borrowed] },
              due_on: { type: :string, format: :date, nullable: true },
              created_at: { type: :string, format: :"date-time" }
            },
            required: %w[id serial_number title author status due_on created_at]
          },
          book_details: {
            allOf: [
              { "$ref" => "#/components/schemas/book" },
              {
                type: :object,
                properties: {
                  current_borrowing: { anyOf: [ { "$ref" => "#/components/schemas/history_entry" }, { type: :object, nullable: true, maxProperties: 0 } ] }
                },
                required: %w[current_borrowing]
              }
            ]
          },
          history_entry: {
            type: :object,
            properties: {
              id: { type: :string, format: :uuid },
              borrowed_at: { type: :string, format: :"date-time" },
              due_on: { type: :string, format: :date },
              returned_at: { type: :string, format: :"date-time", nullable: true },
              reader: { anyOf: [ { "$ref" => "#/components/schemas/reader_with_email" }, { type: :object, nullable: true, maxProperties: 0 } ] }
            },
            required: %w[id borrowed_at due_on returned_at reader]
          },
          borrowing: {
            type: :object,
            properties: {
              id: { type: :string, format: :uuid },
              book_id: { type: :string, format: :uuid },
              borrowed_at: { type: :string, format: :"date-time" },
              due_on: { type: :string, format: :date },
              returned_at: { type: :string, format: :"date-time", nullable: true },
              reader: { anyOf: [ { "$ref" => "#/components/schemas/reader" }, { type: :object, nullable: true, maxProperties: 0 } ] }
            },
            required: %w[id book_id borrowed_at due_on returned_at reader]
          },
          reader: {
            type: :object,
            properties: {
              id: { type: :string, format: :uuid },
              card_number: { type: :string, pattern: "^[0-9]{6}$" },
              full_name: { type: :string }
            },
            required: %w[id card_number full_name]
          },
          reader_with_email: {
            type: :object,
            properties: {
              id: { type: :string, format: :uuid },
              card_number: { type: :string, pattern: "^[0-9]{6}$" },
              full_name: { type: :string },
              email: { type: :string, format: :email }
            },
            required: %w[id card_number full_name email]
          },
          reader_details: {
            type: :object,
            properties: {
              id: { type: :string, format: :uuid },
              card_number: { type: :string, pattern: "^[0-9]{6}$" },
              full_name: { type: :string, maxLength: 255 },
              email: { type: :string, format: :email, maxLength: 254 },
              created_at: { type: :string, format: :"date-time" }
            },
            required: %w[id card_number full_name email created_at]
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
