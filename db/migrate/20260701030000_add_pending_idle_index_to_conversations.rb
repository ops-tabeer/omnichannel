class AddPendingIdleIndexToConversations < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    # Serves the JIVO idle follow-up eligibility query (runs every 10 min per inbox):
    #   inbox_id = ? AND status = pending(2) AND last_activity_at < ? [AND created_at >= ?]
    # Partial on status = 2 so the index only holds pending conversations (a small subset),
    # letting the scan skip the in-memory status filter. `status` enum: pending = 2.
    add_index :conversations, [:inbox_id, :last_activity_at],
              where: 'status = 2',
              name: 'index_conversations_pending_on_inbox_last_activity',
              algorithm: :concurrently
  end
end
