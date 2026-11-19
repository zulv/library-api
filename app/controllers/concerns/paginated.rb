module Paginated
  extend ActiveSupport::Concern
  include Pagy::Method

  included do
    rescue_from Pagy::OptionError, with: :render_invalid_pagination
  end

  private

  def paginate(collection)
    pagination, records = pagy(:offset, collection)
    response.headers.merge!(pagination.headers_hash)
    records
  end

  def render_invalid_pagination
    render json: { error: "invalid pagination params" }, status: :bad_request
  end
end
