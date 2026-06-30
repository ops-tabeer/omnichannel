class CreateJivoAiUsages < ActiveRecord::Migration[7.1]
  def change
    create_table :jivo_ai_usages do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.string :period, null: false
      t.integer :follow_up_count, null: false, default: 0
      t.integer :handoff_count, null: false, default: 0
      t.integer :wait_count, null: false, default: 0

      t.timestamps
    end

    add_index :jivo_ai_usages, %i[account_id period], unique: true
  end
end
