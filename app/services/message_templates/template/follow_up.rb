class MessageTemplates::Template::FollowUp
  pattr_initialize [:conversation!]

  def perform
    return if conversation.account.conversation_follow_up_message.blank?

    if within_messaging_window?
      conversation.messages.create!(follow_up_message_params)
    else
      create_follow_up_not_sent_activity_message
    end
  end

  private

  delegate :contact, :account, to: :conversation

  def within_messaging_window?
    conversation.can_reply?
  end

  def create_follow_up_not_sent_activity_message
    content = I18n.t('conversations.activity.follow_up.not_sent_due_to_messaging_window')
    activity_message_params = {
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: content
    }
    ::Conversations::ActivityMessageJob.perform_later(conversation, activity_message_params) if content
  end

  def follow_up_message_params
    {
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :template,
      content: account.conversation_follow_up_message,
      content_attributes: { 'follow_up_message' => true }
    }
  end
end
