class Jivo::IdleConversationActionJob < ApplicationJob
  queue_as :scheduled_jobs

  ATTEMPT_COUNT_KEY = 'jivo_idle_reminder_count'.freeze

  def perform
    JivoInbox.includes(:jivo_assistant, :inbox).find_each do |jivo_inbox|
      assistant = jivo_inbox.jivo_assistant
      next unless assistant&.idle_action_enabled?

      backfill_cutoff(assistant)
      process_inbox(jivo_inbox.inbox, assistant)
    end
  ensure
    Current.reset
  end

  private

  # Safety net: an assistant enabled without a cutoff (e.g. set before this existed or
  # via console) must not act on the pre-enable backlog. Stamp "now" so only newer
  # conversations qualify from here on.
  def backfill_cutoff(assistant)
    return if assistant.idle_action_enabled_at_value

    assistant.update!(idle_action_enabled_at: Time.current.iso8601)
  end

  def process_inbox(inbox, assistant)
    Current.executed_by = assistant

    idle_conversations(inbox, assistant).find_each do |conversation|
      apply_idle_action(conversation, assistant)
    end
  end

  def idle_conversations(inbox, assistant)
    cutoff = assistant.idle_action_enabled_at_value
    scope = inbox.conversations
                 .pending
                 .where('last_activity_at < ?', assistant.idle_timeout_minutes_value.minutes.ago)
    scope = scope.where('conversations.created_at >= ?', cutoff) if cutoff
    scope.limit(Limits::BULK_ACTIONS_LIMIT)
  end

  def apply_idle_action(conversation, assistant)
    return if reminder_limit_reached?(conversation, assistant)

    I18n.with_locale(conversation.account.locale) do
      create_outgoing_message(conversation, assistant)

      case assistant.idle_action_value
      when JivoAssistant::IDLE_ACTION_RESOLVE
        conversation.resolved!
      when JivoAssistant::IDLE_ACTION_HANDOFF
        handoff_to_agent(conversation)
      when JivoAssistant::IDLE_ACTION_REMINDER
        increment_attempt(conversation)
      end
    end
  rescue StandardError => e
    Rails.logger.error "[JIVO] Idle action failed for conversation #{conversation.id}: #{e.message}"
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
  end

  def reminder_limit_reached?(conversation, assistant)
    return false unless assistant.idle_action_value == JivoAssistant::IDLE_ACTION_REMINDER

    attempt_count(conversation) >= assistant.idle_reminder_limit_value
  end

  # Follow-up attempts already made on this conversation. Read/incremented here so the
  # static (and later AI) follow-up loops share one source of truth for the count.
  def attempt_count(conversation)
    conversation.custom_attributes[ATTEMPT_COUNT_KEY].to_i
  end

  def increment_attempt(conversation)
    conversation.update!(
      custom_attributes: conversation.custom_attributes.merge(ATTEMPT_COUNT_KEY => attempt_count(conversation) + 1)
    )
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
