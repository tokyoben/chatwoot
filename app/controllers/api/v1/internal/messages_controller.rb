# frozen_string_literal: true

# Api::V1::Internal::MessagesController
#
# Internal API endpoint for message interceptor callbacks
# This endpoint receives modified message content from external translation service
#
# Usage:
#   POST /api/v1/internal/messages/:id/interceptor_callback
#
# Headers:
#   Authorization: Bearer <MESSAGE_INTERCEPTOR_API_KEY>
#   Content-Type: application/json
#
# Body:
#   {
#     "message_id": 123,
#     "translated_content": "Translated text here",
#     "metadata": {
#       "source_language": "en",
#       "target_language": "ja",
#       "translation_provider": "google",
#       "confidence_score": 0.95
#     }
#   }

class Api::V1::Internal::MessagesController < Api::V1::Internal::BaseController
  before_action :set_message

  # POST /api/v1/internal/messages/:id/interceptor_callback
  def interceptor_callback
    if params[:translated_content].blank?
      return render json: {
        success: false,
        error: 'translated_content is required'
      }, status: :unprocessable_entity
    end

    # Replace message content using interceptor service
    interceptor = MessageInterceptorService.new(@message)
    success = interceptor.replace_content(
      params[:translated_content],
      params[:metadata]&.to_unsafe_h || {}
    )

    if success
      render json: {
        success: true,
        message_id: @message.id,
        conversation_id: @message.conversation_id,
        updated_at: @message.updated_at
      }, status: :ok
    else
      render json: {
        success: false,
        error: 'Failed to replace message content'
      }, status: :internal_server_error
    end
  rescue StandardError => e
    Rails.logger.error("Internal::MessagesController#interceptor_callback error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))

    render json: {
      success: false,
      error: e.message
    }, status: :internal_server_error
  end

  private

  def set_message
    @message = Message.find_by(id: params[:id])

    unless @message
      render json: {
        success: false,
        error: 'Message not found'
      }, status: :not_found
    end
  end
end
