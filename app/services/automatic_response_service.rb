# frozen_string_literal: true

# AutomaticResponseService - AI-powered automatic responses
#
# When automatic mode is enabled for a conversation, this service:
# 1. Checks if automatic mode is active
# 2. Sends conversation context to RAG server
# 3. Receives AI-generated response
# 4. Posts response as outgoing message from assigned agent
#
# The response goes through normal message flow:
# - Shows in agent's dashboard as if they sent it
# - Gets intercepted and translated for widget user
# - Broadcasts via ActionCable
#
class AutomaticResponseService
  attr_reader :conversation

  # RAG server endpoint for automatic responses
  RAG_AUTO_RESPOND_URL = ENV.fetch('MESSAGE_INTERCEPTOR_URL', 'http://localhost:3001').gsub('/translate', '/auto-respond')
  RAG_TIMEOUT = ENV.fetch('MESSAGE_INTERCEPTOR_TIMEOUT', '30').to_i

  def initialize(conversation)
    @conversation = conversation
  end

  # Check if automatic mode is enabled for this conversation
  def automatic_mode_enabled?
    conversation.additional_attributes&.dig('automatic_mode') == true
  end

  # Generate and send automatic response
  def generate_and_send
    return unless automatic_mode_enabled?
    return unless conversation.assignee.present?

    Rails.logger.info("AutomaticResponse: Generating response for conversation #{conversation.id}")

    # Get AI response from RAG server
    ai_response = fetch_ai_response
    return if ai_response.blank?

    # Create outgoing message from agent
    create_agent_message(ai_response)

    Rails.logger.info("AutomaticResponse: Sent response for conversation #{conversation.id}")
  rescue StandardError => e
    Rails.logger.error("AutomaticResponse: Failed for conversation #{conversation.id}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    # Don't raise - we don't want to break message flow if AI fails
  end

  private

  def fetch_ai_response
    # Get recent conversation history (last 20 messages)
    messages = conversation.messages
                          .where.not(message_type: :activity)
                          .where(private: false)
                          .order(created_at: :asc)
                          .last(20)

    # Format conversation history for RAG server
    conversation_history = messages.map do |msg|
      {
        role: msg.incoming? ? 'user' : 'assistant',
        content: msg.content,
        timestamp: msg.created_at.to_i
      }
    end

    # Call RAG server
    response = HTTParty.post(
      RAG_AUTO_RESPOND_URL,
      headers: {
        'Content-Type' => 'application/json',
        'X-API-Key' => ENV.fetch('MESSAGE_INTERCEPTOR_API_KEY', '')
      },
      body: {
        conversation_id: conversation.id,
        account_id: conversation.account_id,
        conversation_history: conversation_history,
        contact: {
          name: conversation.contact.name,
          email: conversation.contact.email
        }
      }.to_json,
      timeout: RAG_TIMEOUT
    )

    if response.success?
      data = JSON.parse(response.body)
      data['response']
    else
      Rails.logger.error("AutomaticResponse: RAG server error: #{response.code} - #{response.body}")
      nil
    end
  rescue StandardError => e
    Rails.logger.error("AutomaticResponse: Failed to fetch AI response: #{e.message}")
    nil
  end

  def create_agent_message(content)
    # Create message as outgoing from assigned agent
    # This goes through normal message flow including translation
    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      sender: conversation.assignee,
      content: content,
      content_attributes: {
        automation_source: 'ai_automatic_response' # Mark as AI-generated for analytics
      }
    )
  end
end
