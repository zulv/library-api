require "swagger_helper"

RSpec.describe "Books", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers(user) }
  let(:Authorization) { headers["Authorization"] }

  path "/books" do
    get "Lists books" do
      tags "Books"
      produces "application/json"
      description "Returns kept books ordered by creation. Pagination metadata is returned in headers."

      parameter name: :page, in: :query, type: :integer, required: false, description: "Page number, starting at 1"
      parameter name: :limit, in: :query, schema: { type: :integer, minimum: 1, maximum: 100 }, required: false, description: "Page size, default 25, max 100"
      parameter name: :serial_number, in: :query, type: :string, required: false, description: "Exact serial number filter"

      response "200", "books listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/book" }

        header "link", schema: { type: :string }, description: "RFC 8288 links with rels first, prev, next, last"
        header "current-page", schema: { type: :integer }, description: "Current page number"
        header "page-limit", schema: { type: :integer }, description: "Page size"
        header "total-pages", schema: { type: :integer }, description: "Total number of pages"
        header "total-count", schema: { type: :integer }, description: "Total number of books"

        before { create_list(:book, 2) }

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

    post "Creates a book" do
      tags "Books"
      consumes "application/json"
      produces "application/json"

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          book: {
            type: :object,
            properties: {
              serial_number: { type: :string, pattern: "^[0-9]{6}$" },
              title: { type: :string },
              author: { type: :string }
            },
            required: %w[serial_number title author]
          }
        },
        required: %w[book]
      }

      response "201", "book created" do
        schema "$ref" => "#/components/schemas/book"

        let(:payload) { { book: { serial_number: "123456", title: "Dune", author: "Frank Herbert" } } }

        run_test! do |response|
          expect(response.parsed_body).to include("serial_number" => "123456", "title" => "Dune", "author" => "Frank Herbert")
          expect(response.headers["Location"]).to end_with("/books/#{response.parsed_body["id"]}")
          expect(Book.count).to eq(1)
        end
      end

      response "400", "missing book params" do
        schema "$ref" => "#/components/schemas/error"

        let(:payload) { {} }

        run_test! do
          expect(Book.count).to eq(0)
        end
      end

      response "409", "serial number conflict" do
        schema "$ref" => "#/components/schemas/error"

        let(:payload) { { book: { serial_number: "123456", title: "Dune", author: "Frank Herbert" } } }

        before { allow(Book).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique) }

        run_test! do |response|
          expect(response.parsed_body).to eq("error" => "conflict")
        end
      end

      response "422", "validation failed" do
        schema "$ref" => "#/components/schemas/validation_errors"

        let(:payload) { { book: { serial_number: "12", title: "Dune", author: "Frank Herbert" } } }

        run_test! do |response|
          expect(response.parsed_body["errors"]).to have_key("serial_number")
          expect(Book.count).to eq(0)
        end
      end

      response "401", "unauthorized" do
        schema "$ref" => "#/components/schemas/error"

        let(:Authorization) { nil }
        let(:payload) { { book: { serial_number: "123456", title: "Dune", author: "Frank Herbert" } } }

        run_test! do
          expect(Book.count).to eq(0)
        end
      end
    end
  end

  path "/books/{id}" do
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "Book id"

    get "Shows a book" do
      tags "Books"
      produces "application/json"

      description "Returns the book with its current borrowing, or null when the book is available. The full history is available under /books/{book_id}/borrowings."

      response "200", "book found" do
        schema "$ref" => "#/components/schemas/book_details"

        let(:book) { create(:book, serial_number: "123456") }
        let(:reader) { create(:reader, card_number: "654321", full_name: "Ann Smith", email: "ann@example.com") }
        let(:id) { book.id }

        before { create(:borrowing, book:, reader:) }

        run_test! do |response|
          expect(response.parsed_body).to include("id" => book.id, "serial_number" => "123456", "status" => "borrowed")
          expect(response.parsed_body["current_borrowing"]).to include("returned_at" => nil)
          expect(response.parsed_body.dig("current_borrowing", "reader")).to include(
            "id" => reader.id, "card_number" => "654321", "full_name" => "Ann Smith", "email" => "ann@example.com"
          )
        end
      end

      response "404", "book not found" do
        schema "$ref" => "#/components/schemas/error"

        let(:id) { SecureRandom.uuid }

        run_test! do |response|
          expect(response.parsed_body).to eq("error" => "book not found")
        end
      end

      response "401", "unauthorized" do
        schema "$ref" => "#/components/schemas/error"

        let(:Authorization) { nil }
        let(:id) { create(:book).id }

        run_test!
      end
    end

    delete "Deletes a book" do
      tags "Books"
      produces "application/json"
      description "Soft deletes the book. Its serial number stays reserved. A borrowed book can't be deleted."

      response "204", "book deleted" do
        let(:book) { create(:book) }
        let(:id) { book.id }

        run_test! do
          expect(book.reload).to be_discarded
        end
      end

      response "404", "book not found" do
        schema "$ref" => "#/components/schemas/error"

        let(:id) { SecureRandom.uuid }

        run_test!
      end

      response "409", "book is borrowed" do
        schema "$ref" => "#/components/schemas/error"

        let(:book) { create(:book) }
        let(:id) { book.id }

        before { create(:borrowing, book:) }

        run_test! do |response|
          expect(response.parsed_body).to eq("error" => "book is borrowed and can't be removed")
          expect(book.reload).not_to be_discarded
        end
      end

      response "401", "unauthorized" do
        schema "$ref" => "#/components/schemas/error"

        let(:Authorization) { nil }
        let(:book) { create(:book) }
        let(:id) { book.id }

        run_test! do
          expect(book.reload).not_to be_discarded
        end
      end
    end
  end

  describe "GET /books variants" do
    it "shows an available book without a due date" do
      create(:book)

      get "/books", headers: headers

      expect(response.parsed_body.first).to include("status" => "available", "due_on" => nil)
    end

    it "shows a borrowed book with its due date" do
      borrowing = create(:borrowing)

      get "/books", headers: headers

      expect(response.parsed_body.first).to include("status" => "borrowed", "due_on" => borrowing.due_on.iso8601)
    end

    it "shows a returned book as available" do
      create(:borrowing, :returned)

      get "/books", headers: headers

      expect(response.parsed_body.first).to include("status" => "available", "due_on" => nil)
    end

    it "does not expose reader data or history" do
      create(:borrowing)

      get "/books", headers: headers

      expect(response.parsed_body.first.keys).to contain_exactly("id", "serial_number", "title", "author", "status", "due_on", "created_at")
      expect(response.body).not_to include("email")
    end

    it "returns pagination headers for a middle page" do
      create_list(:book, 5)

      get "/books", params: { limit: 2, page: 2 }, headers: headers

      expect(response.headers.to_h).to include(
        "current-page" => "2",
        "page-limit" => "2",
        "total-pages" => "3",
        "total-count" => "5"
      )
    end

    it "returns the requested page of books" do
      books = create_list(:book, 5).sort_by(&:id)

      get "/books", params: { limit: 2, page: 2 }, headers: headers

      expect(response.parsed_body.pluck("id")).to eq(books[2..3].map(&:id))
    end

    it "returns link rels for navigating pages" do
      create_list(:book, 5)

      get "/books", params: { limit: 2, page: 2 }, headers: headers

      expect(response.headers["link"].scan(/rel="(\w+)"/).flatten).to contain_exactly("first", "prev", "next", "last")
    end

    it "caps the limit at 100" do
      create(:book)

      get "/books", params: { limit: 1000 }, headers: headers

      expect(response.headers["page-limit"]).to eq("100")
    end

    it "uses a default limit of 25" do
      create_list(:book, 26)

      get "/books", headers: headers

      expect(response.parsed_body.size).to eq(25)
      expect(response.headers["total-pages"]).to eq("2")
    end

    it "returns an empty array for a page out of range" do
      create_list(:book, 2)

      get "/books", params: { page: 99 }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end

    it "returns an empty array when there are no books" do
      get "/books", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end

    it "orders books by id which is insertion order" do
      first = create(:book)
      second = create(:book)
      third = create(:book)

      get "/books", headers: headers

      expect(response.parsed_body.pluck("id")).to eq([ first.id, second.id, third.id ])
    end

    it "filters by serial number" do
      wanted = create(:book, serial_number: "111111")
      create(:book, serial_number: "222222")

      get "/books", params: { serial_number: "111111" }, headers: headers

      expect(response.parsed_body.pluck("id")).to eq([ wanted.id ])
    end

    it "normalizes surrounding spaces in the serial number filter" do
      wanted = create(:book, serial_number: "100001")
      create(:book, serial_number: "100002")

      get "/books", params: { serial_number: " 100001 " }, headers: headers

      expect(response.parsed_body.pluck("id")).to eq([ wanted.id ])
    end

    it "ignores an array serial number filter" do
      create_list(:book, 2)

      get "/books?serial_number[]=111111", headers: headers

      expect(response.parsed_body.size).to eq(2)
    end

    it "returns an empty array for an unknown serial number" do
      create(:book, serial_number: "111111")

      get "/books", params: { serial_number: "999999" }, headers: headers

      expect(response.parsed_body).to eq([])
    end

    it "ignores a blank serial number filter" do
      create_list(:book, 2)

      get "/books", params: { serial_number: "" }, headers: headers

      expect(response.parsed_body.size).to eq(2)
    end

    it "omits discarded books" do
      kept = create(:book)
      create(:book).discard!

      get "/books", headers: headers

      expect(response.parsed_body.pluck("id")).to eq([ kept.id ])
    end

    it "rejects a negative limit with a clear message" do
      get "/books", params: { limit: -5 }, headers: headers

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to eq("error" => "invalid pagination params")
    end

    it "falls back to the default limit for a zero limit" do
      get "/books", params: { limit: 0 }, headers: headers

      expect(response.headers["page-limit"]).to eq("25")
    end
  end

  describe "POST /books variants" do
    let(:attributes) { { serial_number: "123456", title: "Dune", author: "Frank Herbert" } }

    it "rejects a malformed JSON body" do
      post "/books", params: '{"book":', headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to eq("error" => "invalid JSON")
      expect(Book.count).to eq(0)
    end

    it "strips whitespace from title and author" do
      post "/books", params: { book: attributes.merge(title: "  Dune ", author: " Frank Herbert ") }, as: :json, headers: headers

      expect(response.parsed_body).to include("title" => "Dune", "author" => "Frank Herbert")
    end

    it "stores a serial number stripped of whitespace" do
      post "/books", params: { book: attributes.merge(serial_number: " 100001 ") }, as: :json, headers: headers

      expect(response.parsed_body["serial_number"]).to eq("100001")
    end

    it "accepts an unwrapped JSON body" do
      post "/books", params: attributes, as: :json, headers: headers

      expect(response).to have_http_status(:created)
    end

    it "accepts a wrapped JSON body" do
      post "/books", params: { book: attributes }, as: :json, headers: headers

      expect(response).to have_http_status(:created)
    end

    it "reports all missing attributes" do
      post "/books", params: { book: { serial_number: "123456" } }, as: :json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"].keys).to contain_exactly("title", "author")
    end

    it "rejects a duplicated serial number" do
      create(:book, serial_number: "123456")

      post "/books", params: { book: attributes }, as: :json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to have_key("serial_number")
    end

    it "rejects the serial number of a discarded book" do
      create(:book, serial_number: "123456").discard!

      post "/books", params: { book: attributes }, as: :json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects an array as serial number" do
      post "/books", params: { book: attributes.merge(serial_number: [ "123456" ]) }, as: :json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /books/:id variants" do
    it "returns a null current borrowing for an available book" do
      book = create(:book)

      get "/books/#{book.id}", headers: headers

      expect(response.parsed_body).to include("status" => "available", "due_on" => nil, "current_borrowing" => nil)
    end

    it "returns a null current borrowing for a returned book" do
      book = create(:book)
      create(:borrowing, :returned, book:)

      get "/books/#{book.id}", headers: headers

      expect(response.parsed_body).to include("status" => "available", "current_borrowing" => nil)
    end

    it "does not return a borrowings key" do
      book = create(:book)
      create(:borrowing, :returned, book:)
      create(:borrowing, book:)

      get "/books/#{book.id}", headers: headers

      expect(response.parsed_body).not_to have_key("borrowings")
    end

    it "returns only the open borrowing among past ones" do
      book = create(:book)
      create(:borrowing, :returned, book:, borrowed_at: Time.zone.local(2026, 1, 1, 12))
      current = create(:borrowing, book:, borrowed_at: Time.zone.local(2026, 2, 1, 12))

      get "/books/#{book.id}", headers: headers

      expect(response.parsed_body["current_borrowing"]).to include("id" => current.id, "returned_at" => nil)
    end

    it "shows the due date of the current borrowing" do
      book = create(:book)
      borrowing = create(:borrowing, book:)

      get "/books/#{book.id}", headers: headers

      expect(response.parsed_body).to include("status" => "borrowed", "due_on" => borrowing.due_on.iso8601)
      expect(response.parsed_body["current_borrowing"]).to include("due_on" => borrowing.due_on.iso8601)
    end

    it "returns 404 for a discarded book" do
      book = create(:book)
      book.discard!

      get "/books/#{book.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a malformed id" do
      get "/books/not-a-uuid", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "book not found")
    end
  end

  describe "DELETE /books/:id variants" do
    it "refuses to delete a borrowed book" do
      book = create(:book)
      create(:borrowing, book:)

      delete "/books/#{book.id}", headers: headers

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq("error" => "book is borrowed and can't be removed")
    end

    it "returns 404 when a concurrent delete wins the discard" do
      book = create(:book)
      allow_any_instance_of(Book).to receive(:discard!).and_raise(Discard::RecordNotDiscarded.new("Failed to discard the record", book))

      delete "/books/#{book.id}", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "book not found")
    end

    it "deletes a book after it was returned" do
      book = create(:book)
      create(:borrowing, :returned, book:)

      delete "/books/#{book.id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(book.reload).to be_discarded
    end

    it "returns 404 for an already discarded book" do
      book = create(:book)
      book.discard!

      delete "/books/#{book.id}", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "book not found")
    end

    it "keeps the row in the database" do
      book = create(:book)

      delete "/books/#{book.id}", headers: headers

      expect(Book.exists?(book.id)).to be(true)
    end
  end
end
