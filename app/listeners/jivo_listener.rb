class JivoListener < BaseListener
  def conversation_resolved(event)
    conversation = extract_conversation_and_account(event)[0]
    assistant = conversation&.inbox&.jivo_assistant

    return unless conversation&.inbox&.active_jivo_assistant?

    Jivo::ContactNotesJob.perform_later(conversation, assistant) if assistant.feature_memory.present?
    Jivo::ConversationFaqJob.perform_later(conversation, assistant) if assistant.feature_faq.present?
  end
end
