class ApplicationController < ActionController::API
  include Authentication

  rescue_from ActiveRecord::RecordNotFound,       with: :render_not_found
  rescue_from Discard::RecordNotDiscarded,        with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid,        with: :render_unprocessable_content
  rescue_from ActiveRecord::RecordNotUnique,      with: :render_conflict
  rescue_from ActionController::ParameterMissing, with: :render_bad_request
  rescue_from ConflictError,                      with: :render_domain_conflict

  private

  def render_not_found
    render json: { error: "not found" }, status: :not_found
  end

  def render_unprocessable_content(exception)
    render json: { errors: exception.record.errors }, status: :unprocessable_content
  end

  def render_conflict
    render json: { error: "conflict" }, status: :conflict
  end

  def render_bad_request(exception)
    render json: { error: exception.message }, status: :bad_request
  end

  def render_domain_conflict(exception)
    render json: { error: exception.message }, status: :conflict
  end
end
