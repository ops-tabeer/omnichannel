class Jivo::ContactNotesJob < ApplicationJob
  queue_as :default

  def perform(conversation, assistant)
    return if conversation.blank? || assistant.blank?

    Jivo::Llm::ContactNotesService.new(
      assistant: assistant,
      conversation: conversation
    ).generate_and_update_notes
  end
end
