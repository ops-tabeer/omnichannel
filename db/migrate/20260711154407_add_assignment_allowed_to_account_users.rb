class AddAssignmentAllowedToAccountUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :account_users, :assignment_allowed, :boolean, default: false, null: false
  end
end
