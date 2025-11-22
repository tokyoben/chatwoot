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
  include Events::Types

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
    Rails.logger.info(
      "MessageInterceptor: Checking message #{message.id} " \
      "(type: #{message.message_type}, content: '#{message.content&.truncate(50)}')"
    )

    unless should_intercept?
      Rails.logger.info(
        "MessageInterceptor: Skipping message #{message.id} " \
        "(should_intercept=false, activity=#{message.activity?}, " \
        "private=#{message.private?}, being_replaced=#{message.being_replaced?})"
      )
      return
    end

    Rails.logger.info(
      "MessageInterceptor: Intercepting message #{message.id}, " \
      "will send to #{INTERCEPTOR_BACKEND_URL}"
    )

    # Mark message as pending interception
    mark_as_pending_interception

    # Send to external service asynchronously
    MessageInterceptorJob.perform_later(message.id)
  end

  # Called by external service via callback endpoint
  # Stores BOTH original and translated content - frontend chooses which to display
  def replace_content(new_content, metadata = {})
    return if new_content.blank?
    return if message.content == new_content # No change needed

    # Set flag to prevent loops
    message.instance_variable_set(:@being_replaced, true)

    # Store BOTH versions:
    # - content: sender's original (never changes)
    # - translated_content: recipient's version
    current_attrs = message.additional_attributes || {}
    updated_attrs = current_attrs.merge(
      intercepted: true,
      intercepted_at: Time.current,
      translated_content: new_content,  # Store translation here
      original_content: message.content,  # Store original for reference
      pending_interception: false  # Clear pending flag
    )
    updated_attrs.merge!(metadata.symbolize_keys) if metadata.present?

    # Update ONLY metadata, NOT content
    # This keeps the sender's original in message.content
    update_params = {
      additional_attributes: updated_attrs,
      updated_at: Time.current
    }

    message.update_columns(update_params)

    # Update in-memory object
    message.additional_attributes = updated_attrs

    # NOW dispatch the create events
    # Message contains BOTH versions - frontend decides which to show
    dispatch_create_events_with_translated_content

    # Clear flag
    message.instance_variable_set(:@being_replaced, false)

    Rails.logger.info(
      "MessageInterceptor: Stored translation for message #{message.id} " \
      "(original: '#{message.content}', translated: '#{new_content}')"
    )

    true
  rescue StandardError => e
    Rails.logger.error("MessageInterceptor: Failed to store translation: #{e.message}")
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

  def dispatch_create_events_with_translated_content
    # Dispatch MESSAGE_CREATED event with the translated content
    # This is the same as Message#dispatch_create_events but called after translation
    Rails.configuration.dispatcher.dispatch(
      MESSAGE_CREATED,
      Time.zone.now,
      message: message,
      performed_by: Current.executed_by
    )

    # Handle first reply logic (same as original)
    if message.valid_first_reply?
      Rails.configuration.dispatcher.dispatch(
        FIRST_REPLY_CREATED,
        Time.zone.now,
        message: message,
        performed_by: Current.executed_by
      )
      message.conversation.update(first_reply_created_at: message.created_at, waiting_since: nil)
    else
      update_waiting_since
    end

    Rails.logger.info(
      "MessageInterceptor: Dispatched MESSAGE_CREATED for message #{message.id} with translated content"
    )
  end

  def update_waiting_since
    # Same logic as Message#update_waiting_since
    if message.outgoing? && !message.private && message.conversation.waiting_since.present?
      Rails.configuration.dispatcher.dispatch(
        REPLY_CREATED,
        Time.zone.now,
        waiting_since: message.conversation.waiting_since,
        message: message
      )
      message.conversation.update(waiting_since: nil)
    end
    message.conversation.update(waiting_since: message.created_at) if message.incoming? && message.conversation.waiting_since.blank?
  end
end
