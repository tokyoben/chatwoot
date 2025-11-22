# frozen_string_literal: true

# AutomaticResponseJob - Asynchronously generates AI responses
#
# This job runs the AutomaticResponseService in the background
# to avoid blocking the message interceptor callback.
#
class AutomaticResponseJob < ApplicationJob
  queue_as :default

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation

    AutomaticResponseService.new(conversation).generate_and_send
  rescue StandardError => e
    Rails.logger.error("AutomaticResponseJob: Failed for conversation #{conversation_id}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    # Don't raise - we don't want the job to retry and potentially spam responses
  end
end
