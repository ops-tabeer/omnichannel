class AddAutoReassignmentToInboxes < ActiveRecord::Migration[7.0]
  def change
    add_column :inboxes, :auto_reassignment_enabled, :boolean, default: false, null: false
    add_column :inboxes, :auto_reassignment_threshold, :integer
  end
end
