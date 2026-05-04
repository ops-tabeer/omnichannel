class Jivo::ConversationFaqJob < ApplicationJob
  queue_as :default

  def perform(conversation, assistant, force: false)
    return if conversation.blank? || assistant.blank?

    Jivo::Llm::ConversationFaqService.new(
      assistant: assistant,
      conversation: conversation,
      force: force
    ).generate_and_deduplicate
  end
end
