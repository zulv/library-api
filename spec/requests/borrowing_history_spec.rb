require "swagger_helper"

RSpec.describe "Borrowing history", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers(user) }
  let(:Authorization) { headers["Authorization"] }

  path "/books/{book_id}/borrowings" do
    parameter name: :book_id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "Book id"

    get "Lists the borrowing history of a book" do
      tags "Borrowings"
      produces "application/json"
      description "Returns all borrowings of the book, newest first. The reader is null when anonymized. Pagination metadata is returned in headers."

      parameter name: :page, in: :query, type: :integer, required: false, description: "Page number, starting at 1"
      parameter name: :limit, in: :query, schema: { type: :integer, minimum: 1, maximum: 100 }, required: false, description: "Page size, default 25, max 100"

      let(:book) { create(:book) }
      let(:book_id) { book.id }

      response "200", "history listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/history_entry" }

        header "link", schema: { type: :string }, description: "RFC 8288 links with rels first, prev, next, last"
        header "current-page", schema: { type: :integer }, description: "Current page number"
        header "page-limit", schema: { type: :integer }, description: "Page size"
        header "total-pages", schema: { type: :integer }, description: "Total number of pages"
        header "total-count", schema: { type: :integer }, description: "Total number of borrowings"

        let(:reader) { create(:reader, card_number: "123456", full_name: "Ann Smith", email: "ann@example.com") }

        before do
          create(:borrowing, :returned, book:, borrowed_at: Time.zone.local(2026, 1, 1, 12))
          create(:borrowing, book:, reader:, borrowed_at: Time.zone.local(2026, 2, 1, 12))
        end

        run_test! do |response|
          expect(response.parsed_body.size).to eq(2)
          expect(response.parsed_body.first).to include("returned_at" => nil)
          expect(response.parsed_body.dig(0, "reader")).to include(
            "id" => reader.id, "card_number" => "123456", "full_name" => "Ann Smith", "email" => "ann@example.com"
          )
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

      response "404", "book not found" do
        schema "$ref" => "#/components/schemas/error"

        let(:book_id) { SecureRandom.uuid }

        run_test! do |response|
          expect(response.parsed_body).to eq("error" => "not found")
        end
      end
    end
  end

  describe "GET /books/:book_id/borrowings variants" do
    let(:book) { create(:book) }

    it "returns an empty array for a book that was never borrowed" do
      get "/books/#{book.id}/borrowings", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end

    it "lists the history newest first" do
      oldest = create(:borrowing, :returned, book:, borrowed_at: Time.zone.local(2026, 1, 1, 12))
      newest = create(:borrowing, book:, borrowed_at: Time.zone.local(2026, 3, 1, 12))
      middle = create(:borrowing, :returned, book:, borrowed_at: Time.zone.local(2026, 2, 1, 12))

      get "/books/#{book.id}/borrowings", headers: headers

      expect(response.parsed_body.pluck("id")).to eq([ newest.id, middle.id, oldest.id ])
    end

    it "orders borrowings started at the same moment by id descending" do
      borrowed_at = Time.zone.local(2026, 1, 1, 12)
      first = create(:borrowing, :returned, book:, borrowed_at:)
      second = create(:borrowing, :returned, book:, borrowed_at:)

      get "/books/#{book.id}/borrowings", headers: headers

      expect(response.parsed_body.pluck("id")).to eq([ first.id, second.id ].sort.reverse)
    end

    it "includes both returned and active entries" do
      returned = create(:borrowing, :returned, book:, borrowed_at: Time.zone.local(2026, 1, 1, 12))
      active = create(:borrowing, book:, borrowed_at: Time.zone.local(2026, 2, 1, 12))

      get "/books/#{book.id}/borrowings", headers: headers

      expect(response.parsed_body.to_h { |entry| [ entry["id"], entry["returned_at"] ] }).to match(
        active.id => nil, returned.id => be_present
      )
    end

    it "does not include borrowings of other books" do
      create(:borrowing)
      own = create(:borrowing, book:)

      get "/books/#{book.id}/borrowings", headers: headers

      expect(response.parsed_body.pluck("id")).to eq([ own.id ])
    end

    it "shows a null reader for an anonymized reader" do
      borrowing = create(:borrowing, :returned, book:)
      borrowing.reader.anonymize!

      get "/books/#{book.id}/borrowings", headers: headers

      expect(response.parsed_body.first).to include("id" => borrowing.id, "reader" => nil)
    end

    it "shows a null reader for a detached borrowing" do
      borrowing = create(:borrowing, :returned, book:)
      borrowing.update_columns(reader_id: nil)

      get "/books/#{book.id}/borrowings", headers: headers

      expect(response.parsed_body.first).to include("id" => borrowing.id, "reader" => nil)
    end

    it "returns the requested page of the history" do
      borrowings = 5.times.map { |day| create(:borrowing, :returned, book:, borrowed_at: Time.zone.local(2026, 1, day + 1, 12)) }

      get "/books/#{book.id}/borrowings", params: { limit: 2, page: 2 }, headers: headers

      expect(response.parsed_body.pluck("id")).to eq([ borrowings[2].id, borrowings[1].id ])
    end

    it "returns pagination headers for a middle page" do
      5.times { |day| create(:borrowing, :returned, book:, borrowed_at: Time.zone.local(2026, 1, day + 1, 12)) }

      get "/books/#{book.id}/borrowings", params: { limit: 2, page: 2 }, headers: headers

      expect(response.headers.to_h).to include(
        "current-page" => "2",
        "page-limit" => "2",
        "total-pages" => "3",
        "total-count" => "5"
      )
    end

    it "uses a default limit of 25" do
      26.times { |day| create(:borrowing, :returned, book:, borrowed_at: Time.zone.local(2026, 1, 1, 12) + day.hours) }

      get "/books/#{book.id}/borrowings", headers: headers

      expect(response.parsed_body.size).to eq(25)
      expect(response.headers["total-pages"]).to eq("2")
    end

    it "rejects a negative limit" do
      get "/books/#{book.id}/borrowings", params: { limit: -5 }, headers: headers

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to eq("error" => "invalid pagination params")
    end

    it "returns 404 for a discarded book" do
      book.discard!

      get "/books/#{book.id}/borrowings", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a malformed book id" do
      get "/books/not-a-uuid/borrowings", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
