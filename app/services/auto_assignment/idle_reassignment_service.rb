class AutoAssignment::IdleReassignmentService
  pattr_initialize [:inbox!]

  def perform
    return unless inbox.auto_reassignment_enabled?
    return if inbox.auto_reassignment_threshold.blank?

    idle_conversations.find_each do |conversation|
      reassign(conversation)
    end
  end

  private

  def idle_conversations
    threshold_time = inbox.auto_reassignment_threshold.minutes.ago

    # Covers two cases:
    # 1. Bot handoff — agent never replied (first_reply_created_at nil, waiting_since nil)
    # 2. Mid-conversation — customer replied, agent went silent (waiting_since set)
    # Reassignment resets last_activity_at, so the timer restarts after each reassign.
    # first_reply_created_at IS NULL is the permanent stop — once any agent replies, we stop.
    inbox.conversations
         .open
         .assigned
         .where(first_reply_created_at: nil)
         .where(
           '(waiting_since IS NULL AND last_activity_at < :t) OR (waiting_since IS NOT NULL AND waiting_since < :t)',
           t: threshold_time
         )
  end

  def reassign(conversation)
    old_agent = conversation.assignee
    tried_ids = tried_agent_ids(conversation) + [old_agent&.id].compact

    new_agent = find_available_agent(conversation, tried_ids)
    return unless new_agent

    # Reset last_activity_at so the threshold timer restarts for the new agent
    conversation.update!(
      assignee: new_agent,
      last_activity_at: Time.current,
      additional_attributes: conversation.additional_attributes.merge('auto_reassignment_tried_ids' => tried_ids)
    )

    log_activity(conversation, old_agent&.name, new_agent.name)
  end

  def tried_agent_ids(conversation)
    conversation.additional_attributes['auto_reassignment_tried_ids'] || []
  end

  def find_available_agent(conversation, tried_ids)
    allowed_agent_ids = inbox.member_ids_with_assignment_capacity - tried_ids
    return nil if allowed_agent_ids.empty?

    AutoAssignment::AgentAssignmentService.new(conversation: conversation, allowed_agent_ids: allowed_agent_ids).find_assignee
  end

  def log_activity(conversation, old_agent_name, new_agent_name)
    content = I18n.t(
      'conversations.activity.assignee.auto_reassigned',
      old_agent_name: old_agent_name,
      new_agent_name: new_agent_name
    )
    ::Conversations::ActivityMessageJob.perform_later(
      conversation,
      { account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity, content: content }
    )
  end
end
