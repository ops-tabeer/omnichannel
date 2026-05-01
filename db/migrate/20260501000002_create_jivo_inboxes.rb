class CreateJivoInboxes < ActiveRecord::Migration[7.1]
  def change
    create_table :jivo_inboxes do |t|
      t.references :jivo_assistant, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true, index: { unique: true }
      t.references :account, null: false, foreign_key: true

      t.timestamps
    end
  end
end
