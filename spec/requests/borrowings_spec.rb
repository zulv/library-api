require "swagger_helper"

RSpec.describe "Borrowings", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers(user) }
  let(:Authorization) { headers["Authorization"] }

  path "/books/{book_id}/borrowing" do
    parameter name: :book_id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "Book id"

    post "Borrows a book" do
      tags "Borrowings"
      consumes "application/json"
      produces "application/json"
      description "Borrows the book for 30 days. The due date is counted from the current date in the library time zone."

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: { reader_card_number: { type: :string, pattern: "^[0-9]{6}$" } },
        required: %w[reader_card_number]
      }

      let(:book) { create(:book) }
      let(:reader) { create(:reader, card_number: "123456") }
      let(:book_id) { book.id }
      let(:payload) { { reader_card_number: reader.card_number } }

      response "201", "book borrowed" do
        schema "$ref" => "#/components/schemas/borrowing"

        header "Location", schema: { type: :string }, description: "URL of the borrowed book"

        run_test! do |response|
          expect(response.parsed_body).to include("book_id" => book.id, "returned_at" => nil)
          expect(response.parsed_body["reader"]).to eq("id" => reader.id, "card_number" => "123456", "full_name" => reader.full_name)
          expect(book.borrowings.active.count).to eq(1)
        end
      end

      response "400", "missing or blank reader card number" do
        schema "$ref" => "#/components/schemas/error"

        let(:payload) { {} }

        run_test! do
          expect(Borrowing.count).to eq(0)
        end
      end

      response "401", "unauthorized" do
        schema "$ref" => "#/components/schemas/error"

        let(:Authorization) { nil }

        run_test! do
          expect(Borrowing.count).to eq(0)
        end
      end

      response "404", "book or reader not found" do
        schema "$ref" => "#/components/schemas/error"

        let(:payload) { { reader_card_number: "999999" } }

        run_test! do |response|
          expect(response.parsed_body).to eq("error" => "not found")
          expect(Borrowing.count).to eq(0)
        end
      end

      response "409", "book is already borrowed" do
        schema "$ref" => "#/components/schemas/error"

        before { create(:borrowing, book:) }

        run_test! do |response|
          expect(response.parsed_body).to eq("error" => "book is already borrowed")
          expect(book.borrowings.count).to eq(1)
        end
      end
    end

    delete "Returns a book" do
      tags "Borrowings"
      produces "application/json"
      description "Marks the active borrowing of the book as returned."

      let(:book) { create(:book) }
      let(:book_id) { book.id }

      response "200", "book returned" do
        schema "$ref" => "#/components/schemas/borrowing"

        before { create(:borrowing, book:) }

        run_test! do |response|
          expect(response.parsed_body["returned_at"]).to be_present
          expect(book.reload).not_to be_borrowed
        end
      end

      response "401", "unauthorized" do
        schema "$ref" => "#/components/schemas/error"

        let(:Authorization) { nil }

        before { create(:borrowing, book:) }

        run_test! do
          expect(book.reload).to be_borrowed
        end
      end

      response "404", "book not found or not borrowed" do
        schema "$ref" => "#/components/schemas/error"

        run_test! do |response|
          expect(response.parsed_body).to eq("error" => "not found")
        end
      end
    end
  end

  describe "POST /books/:book_id/borrowing variants" do
    let(:book) { create(:book) }
    let!(:reader) { create(:reader, card_number: "123456") }

    def borrow(card_number = reader.card_number, book_id: book.id)
      post "/books/#{book_id}/borrowing", params: { reader_card_number: card_number }, as: :json, headers: headers
    end

    it "sets the due date 30 days from today" do
      borrow

      expect(response.parsed_body["due_on"]).to eq((Date.current + 30.days).iso8601)
    end

    it "counts the due date from the Warsaw date near midnight UTC" do
      travel_to(Time.utc(2026, 3, 1, 23, 30)) do
        borrow

        expect(response.parsed_body["due_on"]).to eq("2026-04-01")
      end
    end

    it "accepts a card number surrounded by spaces" do
      borrow(" 123456 ")

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("reader", "id")).to eq(reader.id)
    end

    it "points the Location header at the book" do
      borrow

      expect(response.headers["Location"]).to end_with("/books/#{book.id}")
    end

    it "does not expose the reader email" do
      borrow

      expect(response.parsed_body["reader"].keys).to contain_exactly("id", "card_number", "full_name")
    end

    it "marks the book as borrowed" do
      borrow

      expect(book.reload.status).to eq("borrowed")
    end

    it "rejects an empty card number" do
      borrow("")

      expect(response).to have_http_status(:bad_request)
    end

    it "rejects an array card number" do
      borrow([ "123456" ])

      expect(response).to have_http_status(:bad_request)
    end

    it "returns 404 for an unknown card number" do
      borrow("999999")

      expect(response).to have_http_status(:not_found)
      expect(Borrowing.count).to eq(0)
    end

    it "returns 404 for an anonymized reader" do
      reader.anonymize!

      borrow("123456")

      expect(response).to have_http_status(:not_found)
      expect(Borrowing.count).to eq(0)
    end

    it "returns 404 for a discarded book" do
      book.discard!

      borrow

      expect(response).to have_http_status(:not_found)
      expect(Borrowing.count).to eq(0)
    end

    it "returns 404 for an unknown book" do
      borrow(book_id: SecureRandom.uuid)

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a malformed book id" do
      borrow(book_id: "not-a-uuid")

      expect(response).to have_http_status(:not_found)
    end

    it "lets the same reader borrow another book" do
      create(:borrowing, reader:)

      borrow

      expect(response).to have_http_status(:created)
    end

    it "lets another reader borrow the book after a return" do
      create(:borrowing, :returned, book:)

      borrow

      expect(response).to have_http_status(:created)
    end

    it "maps a unique index conflict to 409" do
      allow(Book).to receive(:kept).and_raise(ActiveRecord::RecordNotUnique)

      borrow

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq("error" => "conflict")
    end
  end

  describe "DELETE /books/:book_id/borrowing variants" do
    let(:book) { create(:book) }

    it "returns 404 when the book was already returned" do
      create(:borrowing, book:)
      delete "/books/#{book.id}/borrowing", headers: headers

      delete "/books/#{book.id}/borrowing", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a discarded book" do
      book.discard!

      delete "/books/#{book.id}/borrowing", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "makes the book available again and keeps the history entry" do
      reader = create(:reader)
      create(:borrowing, book:, reader:)

      delete "/books/#{book.id}/borrowing", headers: headers
      get "/books/#{book.id}", headers: headers
      book_response = response.parsed_body
      get "/books/#{book.id}/borrowings", headers: headers

      expect(book_response).to include("status" => "available", "due_on" => nil, "current_borrowing" => nil)
      expect(response.parsed_body.size).to eq(1)
      expect(response.parsed_body.first).to include("returned_at" => be_present)
      expect(response.parsed_body.dig(0, "reader", "id")).to eq(reader.id)
    end

    it "returns the reader of the returned borrowing" do
      reader = create(:reader)
      create(:borrowing, book:, reader:)

      delete "/books/#{book.id}/borrowing", headers: headers

      expect(response.parsed_body.dig("reader", "id")).to eq(reader.id)
    end

    it "does not touch earlier returned borrowings" do
      old = create(:borrowing, :returned, book:, borrowed_at: Time.zone.local(2026, 1, 1, 12))
      create(:borrowing, book:)

      delete "/books/#{book.id}/borrowing", headers: headers

      expect(old.reload.returned_at).to eq(Time.zone.local(2026, 1, 2, 12))
    end
  end
end
