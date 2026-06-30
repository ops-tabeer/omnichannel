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

  # Follow up until the attempt limit is hit, then escalate. The attempt count is checked
  # per conversation (not in the scope) so the limit-reaching run can trigger escalation.
  def apply_idle_action(conversation, assistant)
    I18n.with_locale(conversation.account.locale) do
      if attempt_count(conversation) >= assistant.idle_reminder_limit_value
        escalate(conversation, assistant)
      else
        send_follow_up(conversation, assistant)
      end
    end
  rescue StandardError => e
    Rails.logger.error "[JIVO] Idle action failed for conversation #{conversation.id}: #{e.message}"
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
  end

  def send_follow_up(conversation, assistant)
    create_outgoing_message(conversation, assistant)
    increment_attempt(conversation)
  end

  def escalate(conversation, assistant)
    case assistant.on_limit_action_value
    when JivoAssistant::IDLE_ACTION_HANDOFF
      Jivo::HandoffService.new(conversation: conversation, assistant: assistant, reason: handoff_reason).perform
    when JivoAssistant::IDLE_ACTION_RESOLVE
      conversation.resolved!
    end
    # ON_LIMIT_ACTION_NONE: leave it pending; nothing to do.
  end

  def handoff_reason
    I18n.t('conversations.jivo.idle_handoff_reason',
           default: 'Auto-handed off after the idle follow-up limit was reached.')
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
end
