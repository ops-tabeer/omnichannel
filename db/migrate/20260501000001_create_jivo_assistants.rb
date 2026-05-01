class CreateJivoAssistants < ActiveRecord::Migration[7.1]
  def change
    create_table :jivo_assistants do |t|
      t.string :name, null: false
      t.text :description
      t.jsonb :config, null: false, default: {}
      t.references :account, null: false, foreign_key: true

      t.timestamps
    end
  end
end
