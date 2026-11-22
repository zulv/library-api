class ApplicationController < ActionController::API
  include Authentication

  rescue_from(ActiveRecord::RecordNotFound) { |exception| render_not_found(exception.model) }
  rescue_from(Discard::RecordNotDiscarded) { |exception| render_not_found(exception.record.model_name) }
  rescue_from ActiveRecord::RecordInvalid,        with: :render_unprocessable_content
  rescue_from ActiveRecord::RecordNotUnique,      with: :render_conflict
  rescue_from ActionController::ParameterMissing, with: :render_bad_request
  rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_invalid_json
  rescue_from ConflictError,                      with: :render_domain_conflict

  private

  def render_not_found(model_name)
    render json: { error: not_found_message(model_name) }, status: :not_found
  end

  def not_found_message(model_name)
    model_name ? "#{model_name.to_s.underscore.humanize(capitalize: false)} not found" : "not found"
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

  def render_invalid_json
    render json: { error: "invalid JSON" }, status: :bad_request
  end

  def render_domain_conflict(exception)
    render json: { error: exception.message }, status: :conflict
  end
end
