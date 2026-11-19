class ApplicationController < ActionController::API
  include Authentication

  rescue_from ActiveRecord::RecordNotFound,       with: :render_not_found
  rescue_from ActionController::ParameterMissing, with: :render_bad_request

  private

  def render_not_found
    render json: { error: "not found" }, status: :not_found
  end

  def render_bad_request(exception)
    render json: { error: exception.message }, status: :bad_request
  end
end
