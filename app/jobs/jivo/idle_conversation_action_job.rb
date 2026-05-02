class Jivo::IdleConversationActionJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    JivoInbox.includes(:jivo_assistant, :inbox).find_each do |jivo_inbox|
      assistant = jivo_inbox.jivo_assistant
      next unless assistant.idle_action_enabled?

      process_inbox(jivo_inbox.inbox, assistant)
    end
  ensure
    Current.reset
  end

  private

  def process_inbox(inbox, assistant)
    Current.executed_by = assistant

    idle_conversations(inbox, assistant).find_each do |conversation|
      apply_idle_action(conversation, assistant)
    end
  end

  def idle_conversations(inbox, assistant)
    inbox.conversations
         .pending
         .where('last_activity_at < ?', assistant.idle_timeout_minutes_value.minutes.ago)
         .limit(Limits::BULK_ACTIONS_LIMIT)
  end

  def apply_idle_action(conversation, assistant)
    I18n.with_locale(conversation.account.locale) do
      create_outgoing_message(conversation, assistant)

      case assistant.idle_action_value
      when JivoAssistant::IDLE_ACTION_RESOLVE
        conversation.resolved!
      when JivoAssistant::IDLE_ACTION_HANDOFF
        handoff_to_agent(conversation)
      end
    end
  rescue StandardError => e
    Rails.logger.error "[JIVO] Idle action failed for conversation #{conversation.id}: #{e.message}"
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
  end

  def create_outgoing_message(conversation, assistant)
    conversation.messages.create!(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: assistant,
      content: assistant.idle_message_text,
      private: false
    )
  end

  def handoff_to_agent(conversation)
    conversation.update!(custom_attributes: conversation.custom_attributes.merge('ai_handoff' => true))
    conversation.bot_handoff!
    send_out_of_office_message_if_applicable(conversation)
  end

  def send_out_of_office_message_if_applicable(conversation)
    return if conversation.campaign.present?

    MessageTemplates::Template::OutOfOffice.perform_if_applicable(conversation)
  end
end
