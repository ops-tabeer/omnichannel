class Jivo::Tools::AddLabelToConversationTool < Jivo::Tools::BasePublicTool
  description 'Add a label to a conversation'
  param :label_name, type: 'string', desc: 'The name of the label to add'

  def perform(tool_context, label_name:)
    conversation = find_conversation(tool_context.state)
    return 'Conversation not found' unless conversation

    label_name = label_name&.strip&.downcase
    return 'Label name is required' if label_name.blank?

    label = account_scoped(Label).find_by(title: label_name)
    return 'Label not found' unless label

    conversation.add_labels(label_name)

    log_tool_usage('added_label', conversation_id: conversation.id, label: label_name)

    "Label '#{label_name}' added to conversation ##{conversation.display_id}"
  rescue StandardError => e
    Rails.logger.error "Failed to add label to conversation: #{e.message}"
    raise
  end
end
