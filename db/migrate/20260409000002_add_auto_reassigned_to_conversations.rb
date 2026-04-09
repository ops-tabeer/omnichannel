class AddAutoReassignedToConversations < ActiveRecord::Migration[7.0]
  def change
    add_column :conversations, :auto_reassigned, :boolean, default: false, null: false
  end
end
