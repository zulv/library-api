class SessionsController < ApplicationController
  allow_unauthenticated_access only: :create
  rate_limit to: 10, within: 3.minutes, only: :create, with: :render_too_many_requests
  rate_limit to: 10, within: 3.minutes, only: :create, with: :render_too_many_requests,
    by: -> { User.normalize_value_for(:email_address, credentials[:email_address].to_s) }, name: "email_address"

  def create
    user = User.authenticate_by(email_address: credentials[:email_address], password: credentials[:password])
    return render(json: { error: "invalid credentials" }, status: :unauthorized) unless user

    session = user.sessions.create!(ip_address: request.remote_ip, user_agent: request.user_agent)
    render json: { token: session.signed_id(purpose: :session, expires_in: Session::LIFETIME) }, status: :created
  end

  def destroy
    Current.session.destroy
    head :no_content
  end

  private

  def credentials
    params.permit(:email_address, :password)
  end

  def render_too_many_requests
    render json: { error: "too many requests" }, status: :too_many_requests
  end
end
