class AddTakenAtToConversations < ActiveRecord::Migration[7.0]
  def change
    add_column :conversations, :taken_at, :datetime
  end
end
