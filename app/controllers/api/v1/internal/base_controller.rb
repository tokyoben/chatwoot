# frozen_string_literal: true

class Api::V1::Internal::BaseController < ActionController::API
  # Use ActionController::API as base to avoid all the web-related callbacks
  # This gives us a clean slate for internal API endpoints

  before_action :authenticate_interceptor_request

  private

  def authenticate_interceptor_request
    # Authenticate using API key from headers
    api_key = request.headers['Authorization']&.gsub('Bearer ', '')
    expected_key = ENV.fetch('MESSAGE_INTERCEPTOR_API_KEY', 'your-secret-key-here')

    unless api_key.present? && ActiveSupport::SecurityUtils.secure_compare(api_key, expected_key)
      render json: { error: 'Unauthorized' }, status: :unauthorized
    end
  end
end
