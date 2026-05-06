class Jivo::Tools::HandoffTool < Jivo::Tools::BasePublicTool
  description 'Hand off the conversation to a human agent when instructions, guardrails, or the customer request require escalation'
  param :reason, type: 'string', desc: 'The reason why handoff is needed (optional)', required: false

  def perform(tool_context, reason: nil)
    conversation = find_conversation(tool_context.state)
    return 'Conversation not found' unless conversation

    log_tool_usage('tool_handoff', {
                     conversation_id: conversation.id,
                     reason: reason || 'Agent requested handoff'
                   })

    trigger_handoff(conversation, reason)

    "Conversation handed off to human support team#{" (Reason: #{reason})" if reason}"
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    'Failed to handoff conversation'
  end

  private

  def trigger_handoff(conversation, reason)
    if reason.present?
      conversation.messages.create!(
        message_type: :outgoing,
        private: true,
        sender: @assistant,
        account: conversation.account,
        inbox: conversation.inbox,
        content: reason
      )
    end

    conversation.bot_handoff!

    send_out_of_office_message_if_applicable(conversation)
  end

  def send_out_of_office_message_if_applicable(conversation)
    return if conversation.campaign.present?

    ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(conversation)
  end
end
