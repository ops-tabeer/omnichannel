class CreateJivoScenarios < ActiveRecord::Migration[7.1]
  def change
    create_table :jivo_scenarios do |t|
      t.string :title
      t.text :description
      t.text :instruction
      t.jsonb :tools, default: []
      t.boolean :enabled, default: true, null: false
      t.references :jivo_assistant, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true

      t.timestamps
    end

    add_index :jivo_scenarios, :enabled
    add_index :jivo_scenarios, [:jivo_assistant_id, :enabled]
  end
end
