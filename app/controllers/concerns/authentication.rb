module Authentication
  extend ActiveSupport::Concern
  include ActionController::HttpAuthentication::Token::ControllerMethods

  included do
    before_action :require_authentication
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

  def require_authentication
    resume_session || render_unauthorized
  end

  def resume_session
    Current.session ||= find_session_by_token
  end

  def find_session_by_token
    authenticate_with_http_token { |token, _options| Session.find_signed(token, purpose: :session) }
  end

  def render_unauthorized
    response.headers["WWW-Authenticate"] = "Bearer"
    render json: { error: "unauthorized" }, status: :unauthorized
  end

  def current_user
    Current.user
  end
end
