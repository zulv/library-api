module AuthHelpers
  def auth_headers(user)
    session = create(:session, user: user)
    token = session.signed_id(purpose: :session, expires_in: Session::LIFETIME)
    { "Authorization" => "Bearer #{token}" }
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
