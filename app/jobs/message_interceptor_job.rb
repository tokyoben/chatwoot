# frozen_string_literal: true

# MessageInterceptorJob - Async job to send messages to external interceptor service
#
# This job is enqueued after a message is saved and sends the message content
# to an external translation/processing service. The external service is expected
# to call back with the modified content.

class MessageInterceptorJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless message

    service = MessageInterceptorService.new(message)
    return unless service.should_intercept?

    send_to_external_service(message)
  rescue StandardError => e
    Rails.logger.error("MessageInterceptorJob: Failed for message #{message_id}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise # Re-raise to trigger retry
  end

  private

  def send_to_external_service(message)
    url = MessageInterceptorService::INTERCEPTOR_BACKEND_URL
    timeout = MessageInterceptorService::INTERCEPTOR_TIMEOUT

    Rails.logger.info(
      "MessageInterceptorJob: Sending message #{message.id} to #{url} " \
      "(timeout: #{timeout}s)"
    )

    # Prepare payload
    payload = build_payload(message)

    Rails.logger.debug(
      "MessageInterceptorJob: Payload for message #{message.id}: #{payload.to_json}"
    )

    # Send HTTP POST to external service
    response = HTTParty.post(
      url,
      body: payload.to_json,
      headers: {
        'Content-Type' => 'application/json',
        'X-Chatwoot-Message-Id' => message.id.to_s,
        'X-Chatwoot-Conversation-Id' => message.conversation_id.to_s,
        'X-Chatwoot-Account-Id' => message.account_id.to_s,
        'Authorization' => "Bearer #{interceptor_api_key}"
      },
      timeout: timeout
    )

    if response.success?
      Rails.logger.info("MessageInterceptorJob: Successfully sent message #{message.id} to interceptor")

      # If synchronous response (optional - if your backend returns translation immediately)
      if response.body.present?
        handle_synchronous_response(message, response)
      end
    else
      Rails.logger.error(
        "MessageInterceptorJob: Failed to send message #{message.id}. " \
        "Status: #{response.code}, Body: #{response.body}"
      )
      raise StandardError, "Interceptor service returned #{response.code}"
    end
  end

  def build_payload(message)
    {
      message_id: message.id,
      conversation_id: message.conversation_id,
      account_id: message.account_id,
      inbox_id: message.inbox_id,
      message_type: message.message_type,
      content: message.content,
      content_type: message.content_type,
      sender_type: message.sender_type,
      sender_id: message.sender_id,
      sender_name: message.sender&.name,
      contact_identifier: message.conversation.contact&.identifier,
      conversation_identifier: message.conversation.display_id,
      created_at: message.created_at.iso8601,
      callback_url: callback_url(message),
      metadata: {
        conversation_language: detect_conversation_language(message),
        account_language: message.account.locale || 'en'
      }
    }
  end

  def callback_url(message)
    # Generate callback URL for your external service to call back
    # This should be your Chatwoot instance URL
    host = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
    "#{host}/api/v1/internal/messages/#{message.id}/interceptor_callback"
  end

  def interceptor_api_key
    # API key for authenticating with your external service
    ENV.fetch('MESSAGE_INTERCEPTOR_API_KEY', 'your-secret-key-here')
  end

  def detect_conversation_language(message)
    # Try to detect language from conversation attributes
    message.conversation.additional_attributes&.dig('language') ||
      message.conversation.contact&.additional_attributes&.dig('language') ||
      'auto'
  end

  def handle_synchronous_response(message, response)
    # If your external service returns the translation immediately
    # instead of using the callback endpoint
    begin
      data = JSON.parse(response.body)
      if data['translated_content'].present?
        service = MessageInterceptorService.new(message)
        service.replace_content(
          data['translated_content'],
          {
            source_language: data['source_language'],
            target_language: data['target_language'],
            interceptor_metadata: data['metadata']
          }
        )
      end
    rescue JSON::ParserError => e
      Rails.logger.error("MessageInterceptorJob: Failed to parse response: #{e.message}")
    end
  end
end
