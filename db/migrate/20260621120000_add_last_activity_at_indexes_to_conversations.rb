class AddLastActivityAtIndexesToConversations < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    # The conversation list sorts by `last_activity_at DESC` but had no index on it,
    # so every list load did a full scan + sort of the matching conversations.
    # These cover the two list views (status=all): account-wide "All Conversations"
    # and a single inbox. The existing (account_id, inbox_id, status, assignee_id)
    # index already serves the tab counts.
    add_index :conversations, [:account_id, :last_activity_at],
              order: { last_activity_at: :desc },
              name: 'index_conversations_on_account_id_and_last_activity_at',
              algorithm: :concurrently

    add_index :conversations, [:account_id, :inbox_id, :last_activity_at],
              order: { last_activity_at: :desc },
              name: 'index_conversations_on_account_inbox_last_activity_at',
              algorithm: :concurrently
  end
end
