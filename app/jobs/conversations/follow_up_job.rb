class Conversations::FollowUpJob < ApplicationJob
  queue_as :low

  def perform(account:)
    return unless account.feature_enabled?('conversation_follow_up')
    return if account.conversation_follow_up_message.blank?

    wait_time = account.conversation_follow_up_wait_time.to_i
    max_count = account.conversation_follow_up_max_count.to_i.clamp(1, 10)
    after_bot = account.conversation_follow_up_after_bot.present?
    after_agent = account.conversation_follow_up_after_agent.present?

    # Default to both if neither is explicitly set (backwards compatibility)
    if account.conversation_follow_up_after_bot.nil? && account.conversation_follow_up_after_agent.nil?
      after_bot = true
      after_agent = true
    end

    return unless after_bot || after_agent

    # limiting the number of conversations to avoid any performance issues
    eligible_conversations = account.conversations
                                    .follow_up_eligible(wait_time)
                                    .where.not(contact_id: nil)
                                    .limit(Limits::BULK_ACTIONS_LIMIT)

    eligible_conversations.each do |conversation|
      next unless conversation.needs_follow_up?(wait_time, max_count, after_bot: after_bot, after_agent: after_agent)

      send_follow_up(conversation)
    rescue StandardError => e
      ChatwootExceptionTracker.new(e, account: account).capture_exception
    end
  end

  private

  def send_follow_up(conversation)
    ::MessageTemplates::Template::FollowUp.new(conversation: conversation).perform
    conversation.increment_follow_up_count!
  end
end
