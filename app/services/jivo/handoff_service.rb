class Jivo::HandoffService
  pattr_initialize [:conversation!, :assistant!, [:reason, nil]]

  # Single source of truth for a JIVO handoff: optional private reason note, mark
  # ai_handoff (so inbox idle reassignment can take over), flip to open via
  # bot_handoff!, then send the out-of-office message when applicable. Reused by the
  # V2 handoff tool and the idle follow-up job; V1 can adopt it later.
  def perform
    post_reason_note
    conversation.update!(custom_attributes: conversation.custom_attributes.merge('ai_handoff' => true))
    conversation.bot_handoff!
    send_out_of_office_message_if_applicable
  end

  private

  def post_reason_note
    return if reason.blank?

    conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      sender: assistant,
      account: conversation.account,
      inbox: conversation.inbox,
      content: reason
    )
  end

  def send_out_of_office_message_if_applicable
    return if conversation.campaign.present?

    ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(conversation)
  end
end
