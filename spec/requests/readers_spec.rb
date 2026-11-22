require "swagger_helper"

RSpec.describe "Readers", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers(user) }
  let(:Authorization) { headers["Authorization"] }

  path "/readers" do
    get "Lists readers" do
      tags "Readers"
      produces "application/json"
      description "Returns identified readers ordered by creation without email. Anonymized readers are omitted. Pagination metadata is returned in headers."

      parameter name: :page, in: :query, type: :integer, required: false, description: "Page number, starting at 1"
      parameter name: :limit, in: :query, schema: { type: :integer, minimum: 1, maximum: 100 }, required: false, description: "Page size, default 25, max 100"
      parameter name: :card_number, in: :query, type: :string, required: false, description: "Exact card number filter"

      response "200", "readers listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/reader" }

        header "link", schema: { type: :string }, description: "RFC 8288 links with rels first, prev, next, last"
        header "current-page", schema: { type: :integer }, description: "Current page number"
        header "page-limit", schema: { type: :integer }, description: "Page size"
        header "total-pages", schema: { type: :integer }, description: "Total number of pages"
        header "total-count", schema: { type: :integer }, description: "Total number of readers"

        before { create_list(:reader, 2) }

        run_test! do |response|
          expect(response.parsed_body.size).to eq(2)
          expect(response.headers["total-count"]).to eq("2")
        end
      end

      response "400", "invalid pagination params" do
        schema "$ref" => "#/components/schemas/error"

        let(:limit) { -1 }

        run_test! do |response|
          expect(response.parsed_body).to eq("error" => "invalid pagination params")
        end
      end

      response "401", "unauthorized" do
        schema "$ref" => "#/components/schemas/error"

        let(:Authorization) { nil }

        run_test! do |response|
          expect(response.parsed_body).to eq("error" => "unauthorized")
        end
      end
    end

    post "Creates a reader" do
      tags "Readers"
      consumes "application/json"
      produces "application/json"
      description "Creates a reader. Full name and email are stored encrypted. Email is lowercased."

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          reader: {
            type: :object,
            properties: {
              card_number: { type: :string, pattern: "^[0-9]{6}$" },
              full_name: { type: :string, maxLength: 255 },
              email: { type: :string, format: :email, maxLength: 254 }
            },
            required: %w[card_number full_name email]
          }
        },
        required: %w[reader]
      }

      response "201", "reader created" do
        schema "$ref" => "#/components/schemas/reader_details"

        let(:payload) { { reader: { card_number: "123456", full_name: "Ann Smith", email: "ann@example.com" } } }

        run_test! do |response|
          expect(response.parsed_body).to include("card_number" => "123456", "full_name" => "Ann Smith", "email" => "ann@example.com")
          expect(response.headers["Location"]).to end_with("/readers/#{response.parsed_body["id"]}")
          expect(Reader.count).to eq(1)
        end
      end

      response "400", "missing reader params" do
        schema "$ref" => "#/components/schemas/error"

        let(:payload) { {} }

        run_test! do
          expect(Reader.count).to eq(0)
        end
      end

      response "409", "card number or email conflict" do
        schema "$ref" => "#/components/schemas/error"

        let(:payload) { { reader: { card_number: "123456", full_name: "Ann Smith", email: "ann@example.com" } } }

        before { allow(Reader).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique) }

        run_test! do |response|
          expect(response.parsed_body).to eq("error" => "conflict")
        end
      end

      response "422", "validation failed" do
        schema "$ref" => "#/components/schemas/validation_errors"

        let(:payload) { { reader: { card_number: "12", full_name: "Ann Smith", email: "ann@example.com" } } }

        run_test! do |response|
          expect(response.parsed_body["errors"]).to have_key("card_number")
          expect(Reader.count).to eq(0)
        end
      end

      response "401", "unauthorized" do
        schema "$ref" => "#/components/schemas/error"

        let(:Authorization) { nil }
        let(:payload) { { reader: { card_number: "123456", full_name: "Ann Smith", email: "ann@example.com" } } }

        run_test! do
          expect(Reader.count).to eq(0)
        end
      end
    end
  end

  path "/readers/{id}" do
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "Reader id"

    get "Shows a reader" do
      tags "Readers"
      produces "application/json"

      response "200", "reader found" do
        schema "$ref" => "#/components/schemas/reader_details"

        let(:reader) { create(:reader, card_number: "123456", email: "ann@example.com") }
        let(:id) { reader.id }

        run_test! do |response|
          expect(response.parsed_body).to include("id" => reader.id, "card_number" => "123456", "email" => "ann@example.com")
        end
      end

      response "404", "reader not found or anonymized" do
        schema "$ref" => "#/components/schemas/error"

        let(:id) { SecureRandom.uuid }

        run_test! do |response|
          expect(response.parsed_body).to eq("error" => "reader not found")
        end
      end

      response "401", "unauthorized" do
        schema "$ref" => "#/components/schemas/error"

        let(:Authorization) { nil }
        let(:id) { create(:reader).id }

        run_test!
      end
    end

    delete "Anonymizes a reader" do
      tags "Readers"
      produces "application/json"
      description "Clears the reader's personal data and keeps the row. The card number and email become reusable. A reader with a borrowed book can't be anonymized."

      response "204", "reader anonymized" do
        let(:reader) { create(:reader) }
        let(:id) { reader.id }

        run_test! do
          expect(reader.reload).to be_anonymized
        end
      end

      response "404", "reader not found or already anonymized" do
        schema "$ref" => "#/components/schemas/error"

        let(:id) { SecureRandom.uuid }

        run_test!
      end

      response "409", "reader has a borrowed book" do
        schema "$ref" => "#/components/schemas/error"

        let(:reader) { create(:reader) }
        let(:id) { reader.id }

        before { create(:borrowing, reader:) }

        run_test! do |response|
          expect(response.parsed_body).to eq("error" => "reader has a borrowed book")
          expect(reader.reload).not_to be_anonymized
        end
      end

      response "401", "unauthorized" do
        schema "$ref" => "#/components/schemas/error"

        let(:Authorization) { nil }
        let(:reader) { create(:reader) }
        let(:id) { reader.id }

        run_test! do
          expect(reader.reload).not_to be_anonymized
        end
      end
    end
  end

  describe "GET /readers variants" do
    it "does not expose email in the list" do
      create(:reader)

      get "/readers", headers: headers

      expect(response.parsed_body.first.keys).to contain_exactly("id", "card_number", "full_name")
    end

    it "returns pagination headers for a middle page" do
      create_list(:reader, 5)

      get "/readers", params: { limit: 2, page: 2 }, headers: headers

      expect(response.headers.to_h).to include(
        "current-page" => "2",
        "page-limit" => "2",
        "total-pages" => "3",
        "total-count" => "5"
      )
    end

    it "returns readers ordered by id which is insertion order" do
      first = create(:reader)
      second = create(:reader)

      get "/readers", headers: headers

      expect(response.parsed_body.pluck("id")).to eq([ first.id, second.id ])
    end

    it "returns an empty array when there are no readers" do
      get "/readers", headers: headers

      expect(response.parsed_body).to eq([])
    end

    it "filters by card number" do
      wanted = create(:reader, card_number: "111111")
      create(:reader, card_number: "222222")

      get "/readers", params: { card_number: "111111" }, headers: headers

      expect(response.parsed_body.pluck("id")).to eq([ wanted.id ])
    end

    it "normalizes surrounding spaces in the card number filter" do
      wanted = create(:reader, card_number: "100001")
      create(:reader, card_number: "100002")

      get "/readers", params: { card_number: " 100001 " }, headers: headers

      expect(response.parsed_body.pluck("id")).to eq([ wanted.id ])
    end

    it "returns an empty array for an unknown card number" do
      create(:reader, card_number: "111111")

      get "/readers", params: { card_number: "999999" }, headers: headers

      expect(response.parsed_body).to eq([])
    end

    it "ignores an array card number filter" do
      create_list(:reader, 2)

      get "/readers?card_number[]=111111", headers: headers

      expect(response.parsed_body.size).to eq(2)
    end

    it "omits anonymized readers" do
      kept = create(:reader)
      create(:reader).anonymize!

      get "/readers", headers: headers

      expect(response.parsed_body.pluck("id")).to eq([ kept.id ])
    end

    it "counts only identified readers in the total" do
      create(:reader)
      create(:reader, :anonymized)

      get "/readers", headers: headers

      expect(response.headers["total-count"]).to eq("1")
    end
  end

  describe "POST /readers variants" do
    let(:attributes) { { card_number: "123456", full_name: "Ann Smith", email: "ann@example.com" } }

    it "strips whitespace from card number and full name" do
      post "/readers", params: { reader: attributes.merge(card_number: " 123456 ", full_name: "  Ann Smith ") }, as: :json, headers: headers

      expect(response.parsed_body).to include("card_number" => "123456", "full_name" => "Ann Smith")
    end

    it "strips and downcases the email" do
      post "/readers", params: { reader: attributes.merge(email: "  Ann@Example.COM ") }, as: :json, headers: headers

      expect(response.parsed_body["email"]).to eq("ann@example.com")
    end

    it "points the Location header at the new reader" do
      post "/readers", params: { reader: attributes }, as: :json, headers: headers

      expect(response.headers["Location"]).to end_with("/readers/#{Reader.last.id}")
    end

    it "reports all missing attributes" do
      post "/readers", params: { reader: { card_number: "123456" } }, as: :json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"].keys).to contain_exactly("full_name", "email")
    end

    it "rejects a malformed email" do
      post "/readers", params: { reader: attributes.merge(email: "nope") }, as: :json, headers: headers

      expect(response.parsed_body["errors"]).to have_key("email")
    end

    it "rejects a full name longer than 255 characters" do
      post "/readers", params: { reader: attributes.merge(full_name: "a" * 256) }, as: :json, headers: headers

      expect(response.parsed_body["errors"]).to have_key("full_name")
    end

    it "rejects a duplicated card number" do
      create(:reader, card_number: "123456")

      post "/readers", params: { reader: attributes }, as: :json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to have_key("card_number")
    end

    it "rejects a duplicated email in a different case" do
      create(:reader, email: "ann@example.com")

      post "/readers", params: { reader: attributes.merge(card_number: "654321", email: "ANN@example.com") }, as: :json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to have_key("email")
    end

    it "accepts the card number of an anonymized reader" do
      create(:reader, card_number: "123456").anonymize!

      post "/readers", params: { reader: attributes }, as: :json, headers: headers

      expect(response).to have_http_status(:created)
    end
  end

  describe "GET /readers/:id variants" do
    it "returns 404 for an anonymized reader" do
      reader = create(:reader)
      reader.anonymize!

      get "/readers/#{reader.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a malformed id" do
      get "/readers/not-a-uuid", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /readers/:id variants" do
    it "anonymizes a reader after the book was returned" do
      reader = create(:reader)
      create(:borrowing, :returned, reader:)

      delete "/readers/#{reader.id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(reader.reload).to be_anonymized
    end

    it "keeps the borrowing history after anonymization" do
      reader = create(:reader)
      borrowing = create(:borrowing, :returned, reader:)

      delete "/readers/#{reader.id}", headers: headers

      expect(Borrowing.exists?(borrowing.id)).to be(true)
    end

    it "keeps the row in the database" do
      reader = create(:reader)

      delete "/readers/#{reader.id}", headers: headers

      expect(Reader.exists?(reader.id)).to be(true)
    end

    it "clears the personal data" do
      reader = create(:reader)

      delete "/readers/#{reader.id}", headers: headers

      expect(reader.reload.attributes.values_at("card_number", "full_name", "email")).to eq([ nil, nil, nil ])
    end

    it "returns 404 for an already anonymized reader" do
      reader = create(:reader)
      reader.anonymize!

      delete "/readers/#{reader.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
