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
      elsif assistant.idle_use_ai_enabled?
        ai_follow_up(conversation, assistant)
      else
        post_follow_up(conversation, assistant, assistant.idle_message_text)
      end
    end
  rescue StandardError => e
    Rails.logger.error "[JIVO] Idle action failed for conversation #{conversation.id}: #{e.message}"
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
  end

  # AI decides: follow_up (send + count), handoff (escalate now), or wait (count, and
  # hand off in the same run if this wait reaches the limit). Any failure degrades to wait.
  def ai_follow_up(conversation, assistant)
    result = Jivo::Tasks::IdleFollowUpService.new(assistant: assistant, conversation: conversation).perform
    JivoAiUsage.record_action(conversation.account, result[:action],
                              input_tokens: result[:input_tokens], output_tokens: result[:output_tokens])

    case result[:action]
    when 'follow_up'
      post_follow_up(conversation, assistant, result[:message])
    when 'handoff'
      handoff(conversation, assistant, ai_handoff_reason)
    else # 'wait' (and any safe fallback)
      increment_attempt(conversation)
      escalate(conversation, assistant) if attempt_count(conversation) >= assistant.idle_reminder_limit_value
    end
  end

  def post_follow_up(conversation, assistant, content)
    create_outgoing_message(conversation, assistant, content.presence || assistant.idle_message_text)
    increment_attempt(conversation)
  end

  # Deterministic backstop once the limit is hit: handoff (default) or leave pending (none).
  def escalate(conversation, assistant)
    handoff(conversation, assistant, limit_handoff_reason) if assistant.on_limit_action_value == JivoAssistant::IDLE_ACTION_HANDOFF
  end

  # Direct handoff — used by the AI 'handoff' action and the limit backstop. The reason
  # is the private note posted on the conversation, so it must reflect why we handed off.
  def handoff(conversation, assistant, reason)
    Jivo::HandoffService.new(conversation: conversation, assistant: assistant, reason: reason).perform
  end

  def limit_handoff_reason
    I18n.t('conversations.jivo.idle_handoff_reason',
           default: 'Auto-handed off after the idle follow-up limit was reached.')
  end

  def ai_handoff_reason
    I18n.t('conversations.jivo.idle_ai_handoff_reason',
           default: 'Auto-handed off by JIVO idle follow-up.')
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

  def create_outgoing_message(conversation, assistant, content)
    conversation.messages.create!(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: assistant,
      content: content,
      private: false
    )
  end
end
