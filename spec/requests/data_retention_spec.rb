require "rails_helper"

RSpec.describe "Data retention", type: :request do
  let(:user) { create(:user) }

  it "hides the reader of a detached borrowing and keeps the recent one" do
    book = create(:book)
    old = create(:borrowing, book:, borrowed_at: 3.years.ago, returned_at: 3.years.ago + 5.days)
    recent = create(:borrowing, book:, borrowed_at: 1.month.ago, returned_at: 1.month.ago + 5.days)
    headers = auth_headers(user)
    AnonymizeOldBorrowingsJob.perform_now

    get "/books/#{book.id}", headers: headers

    entries = response.parsed_body["borrowings"].index_by { |entry| entry["id"] }
    expect(entries.fetch(old.id)).to include("reader" => nil)
    expect(entries.fetch(recent.id).dig("reader", "id")).to eq(recent.reader_id)
  end

  it "keeps a fresh session authenticated after the purge" do
    headers = auth_headers(user)
    PurgeExpiredSessionsJob.perform_now

    get "/books", headers: headers

    expect(response).to have_http_status(:ok)
  end

  it "rejects the token of a purged expired session" do
    expired = create(:session, user:, created_at: Session::LIFETIME.ago - 1.minute)
    token = expired.signed_id(purpose: :session, expires_in: Session::LIFETIME)
    PurgeExpiredSessionsJob.perform_now

    get "/books", headers: { "Authorization" => "Bearer #{token}" }

    expect(Session.exists?(expired.id)).to be(false)
    expect(response).to have_http_status(:unauthorized)
  end
end
