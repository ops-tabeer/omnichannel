class CreateJivoAssistantResponses < ActiveRecord::Migration[7.1]
  def change
    create_table :jivo_assistant_responses do |t|
      t.string :question, null: false
      t.text :answer, null: false
      t.vector :embedding, limit: 1536
      t.references :jivo_assistant, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.bigint :documentable_id
      t.string :documentable_type
      t.integer :status, default: 1, null: false

      t.timestamps
    end

    add_index :jivo_assistant_responses, :status
    add_index :jivo_assistant_responses, [:documentable_id, :documentable_type],
              name: 'idx_jivo_resp_on_documentable'
    add_index :jivo_assistant_responses, :embedding,
              using: :ivfflat,
              name: 'idx_jivo_resp_embedding'
  end
end
