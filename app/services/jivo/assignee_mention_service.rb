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
    mention = "[@#{name}](mention://user/#{assignee.id}/#{ERB::Util.url_encode(name)})"
    ["#{mention} a new lead has been assigned to you.", contact_details].compact.join("\n\n")
  end

  # Surfaces the contact details Jivo captured (incl. a phone/email read from a
  # shared image) so the agent sees them right in the mention note.
  def contact_details
    contact = conversation.contact
    return if contact.blank?

    lines = []
    lines << "Name: #{contact.name}" if contact.name.present?
    lines << "Phone: #{contact_phone(contact)}" if contact_phone(contact).present?
    lines << "Email: #{contact.email}" if contact.email.present?
    return if lines.empty?

    (['Contact details:'] + lines).join("\n")
  end

  def contact_phone(contact)
    contact.phone_number.presence || contact.additional_attributes['raw_phone_number'].presence
  end
end
