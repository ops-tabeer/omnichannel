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
    Jivo::HandoffService.new(conversation: conversation, assistant: @assistant, reason: reason).perform
  end
end
