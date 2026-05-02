class Jivo::ConversationFaqJob < ApplicationJob
  queue_as :default

  def perform(conversation, assistant)
    return if conversation.blank? || assistant.blank?

    Jivo::Llm::ConversationFaqService.new(
      assistant: assistant,
      conversation: conversation
    ).generate_and_deduplicate
  end
end
