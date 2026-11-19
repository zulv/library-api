require "rails_helper"

RSpec.describe "Readers logging", type: :request do
  let(:headers) { auth_headers(create(:user)) }
  let(:capture) { StringIO.new }
  let(:full_name) { "Zenobia Quimby" }
  let(:email) { "zenobia.quimby@example.com" }
  let(:card_number) { "918273" }

  def with_captured_logs
    original_level = Rails.logger.level
    Rails.logger.level = Logger::DEBUG
    Rails.logger.broadcast_to(ActiveSupport::Logger.new(capture))
    yield
  ensure
    Rails.logger.broadcasts.last.then { |logger| Rails.logger.stop_broadcasting_to(logger) }
    Rails.logger.level = original_level
  end

  def logs
    capture.string
  end

  it "keeps personal data out of the logs when creating a reader" do
    with_captured_logs do
      post "/readers", params: { reader: { card_number:, full_name:, email: } }, as: :json, headers: headers
    end

    expect(logs).to include("Parameters:", "[FILTERED]", "Reader Create")
    expect(logs).not_to include(full_name, email, card_number)
  end

  it "keeps personal data out of the logs when showing a reader" do
    reader = create(:reader, card_number:, full_name:, email:)

    with_captured_logs do
      get "/readers/#{reader.id}", headers: headers
    end

    expect(logs).to include("Reader Load", "GET \"/readers/#{reader.id}\"")
    expect(logs).not_to include(full_name, email, card_number)
  end

  it "keeps personal data out of the logs when filtering by card number" do
    create(:reader, card_number:, full_name:, email:)

    with_captured_logs do
      get "/readers", params: { card_number: }, headers: headers
    end

    expect(logs).to include("Parameters:", "[FILTERED]", "Reader Load")
    expect(logs).not_to include(full_name, email, card_number)
  end
end
