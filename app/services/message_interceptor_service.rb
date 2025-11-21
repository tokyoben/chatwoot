# frozen_string_literal: true

# MessageInterceptorService - MITM Interceptor for seamless message translation
#
# This service intercepts messages before they are saved and sends them to an
# external translation service. The original message content is replaced with
# the translated version without creating new messages.
#
# Flow:
# 1. Message is about to be saved (before_save hook)
# 2. Send message to external translation service
# 3. External service processes and calls back /api/v1/internal/messages/:id/interceptor_callback
# 4. Replace message content using update_columns (bypasses callbacks)
# 5. Broadcast updated content via ActionCable
# 6. Original webhooks fire with original content (before replacement)

class MessageInterceptorService
  attr_reader :message

  # Your external translation service URL
  INTERCEPTOR_BACKEND_URL = ENV.fetch('MESSAGE_INTERCEPTOR_URL', 'http://localhost:3001/translate')
  INTERCEPTOR_TIMEOUT = ENV.fetch('MESSAGE_INTERCEPTOR_TIMEOUT', '5').to_i

  def initialize(message)
    @message = message
  end

  # Called before message is saved
  # Returns true to continue saving, false to abort
  def should_intercept?
    return false if message.content.blank?
    return false if message.activity? # Don't intercept activity messages
    return false if message.private? # Don't intercept private notes
    return false if message.being_replaced? # Prevent loops during replacement

    # Only intercept incoming and outgoing messages
    message.incoming? || message.outgoing?
  end

  # Send message to external interceptor service
  # This happens AFTER the message is saved to DB
  def send_to_interceptor
    return unless should_intercept?

    # Mark message as pending interception
    mark_as_pending_interception

    # Send to external service asynchronously
    MessageInterceptorJob.perform_later(message.id)
  end

  # Called by external service via callback endpoint
  def replace_content(new_content, metadata = {})
    return if new_content.blank?
    return if message.content == new_content # No change needed

    # Set flag to prevent loops
    message.instance_variable_set(:@being_replaced, true)

    # Update content WITHOUT triggering callbacks or validations
    # This prevents webhook loops and additional after_save hooks
    message.update_columns(
      content: new_content,
      processed_message_content: process_content(new_content),
      updated_at: Time.current
    )

    # Update additional metadata if provided
    if metadata.present?
      current_attrs = message.additional_attributes || {}
      message.update_columns(
        additional_attributes: current_attrs.merge(
          intercepted: true,
          intercepted_at: Time.current,
          **metadata.symbolize_keys
        )
      )
    end

    # Manually broadcast the updated content to all listeners
    broadcast_updated_message

    # Clear flag
    message.instance_variable_set(:@being_replaced, false)

    Rails.logger.info(
      "MessageInterceptor: Replaced content for message #{message.id} " \
      "(conversation: #{message.conversation_id})"
    )

    true
  rescue StandardError => e
    Rails.logger.error("MessageInterceptor: Failed to replace content: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    false
  end

  private

  def mark_as_pending_interception
    current_attrs = message.additional_attributes || {}
    message.update_columns(
      additional_attributes: current_attrs.merge(
        pending_interception: true,
        interception_sent_at: Time.current
      )
    )
  end

  def process_content(content)
    # Process the content same way as Message model does
    # This ensures proper formatting
    return content if content.blank?

    # Basic processing - extend as needed
    content.strip
  end

  def broadcast_updated_message
    # Reload to get updated attributes
    message.reload

    # Broadcast to ActionCable (same as when message is created)
    tokens = user_tokens + contact_tokens

    return if tokens.blank?

    payload = message.push_event_data.merge(account_id: message.account_id)

    # Broadcast as MESSAGE_UPDATED event
    ActionCableBroadcastJob.perform_later(tokens.uniq, 'message.updated', payload)
  end

  def user_tokens
    # Get tokens for all agents/members who should receive this update
    members = message.conversation.inbox.members
    account = message.account

    members.map { |member| "user_#{account.id}_#{member.id}" }
  end

  def contact_tokens
    # Get tokens for the contact (user in widget)
    contact_inbox = message.conversation.contact_inbox
    return [] unless contact_inbox&.pubsub_token

    ["contact_#{contact_inbox.pubsub_token}"]
  end
end
