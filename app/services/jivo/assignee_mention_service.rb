class Jivo::AssigneeMentionService
  pattr_initialize [:conversation!]

  def perform
    return unless conversation.custom_attributes['ai_handoff']

    assistant = conversation.inbox.jivo_assistant
    assignee = conversation.assignee
    return if assistant.blank? || assignee.blank?

    conversation.messages.create!(
      account: conversation.account,
      inbox: conversation.inbox,
      sender: assistant,
      message_type: :outgoing,
      private: true,
      content: mention_content(assignee)
    )
  end

  private

  def mention_content(assignee)
    name = assignee.available_name
    "[@#{name}](mention://user/#{assignee.id}/#{ERB::Util.url_encode(name)}) a new lead has been assigned to you."
  end
end
