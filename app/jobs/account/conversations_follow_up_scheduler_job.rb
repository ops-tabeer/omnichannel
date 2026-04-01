class Account::ConversationsFollowUpSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.with_follow_up_enabled.find_each(batch_size: 100) do |account|
      next unless account.feature_enabled?('conversation_follow_up')

      Conversations::FollowUpJob.perform_later(account: account)
    end
  end
end
