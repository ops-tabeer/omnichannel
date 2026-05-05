class Jivo::Tools::UpdatePriorityTool < Jivo::Tools::BasePublicTool
  description 'Update the priority of a conversation'
  param :priority, type: 'string', desc: 'The priority level: low, medium, high, urgent, or nil to remove priority'

  def perform(tool_context, priority:)
    conversation = find_conversation(tool_context.state)
    return 'Conversation not found' unless conversation

    normalized = normalize_priority(priority)
    return "Invalid priority. Valid options: #{valid_priority_options}" unless valid_priority?(normalized)

    log_tool_usage('update_priority', { conversation_id: conversation.id, priority: priority })

    conversation.update!(priority: normalized)
    "Priority updated to '#{normalized || 'none'}' for conversation ##{conversation.display_id}"
  end

  def permissions
    %w[conversation_manage conversation_unassigned_manage conversation_participating_manage]
  end

  private

  def normalize_priority(priority)
    return nil if priority == 'nil' || priority.blank?

    priority.downcase
  end

  def valid_priority?(priority)
    valid_priorities.include?(priority)
  end

  def valid_priorities
    @valid_priorities ||= [nil] + Conversation.priorities.keys
  end

  def valid_priority_options
    (valid_priorities.compact + ['nil']).join(', ')
  end
end
