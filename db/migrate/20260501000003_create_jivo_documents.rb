class CreateJivoDocuments < ActiveRecord::Migration[7.1]
  def change
    create_table :jivo_documents do |t|
      t.string :name
      t.string :external_link, null: false
      t.text :content
      t.references :jivo_assistant, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.integer :status, default: 0, null: false
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :jivo_documents, [:jivo_assistant_id, :external_link], unique: true,
              name: 'index_jivo_documents_on_assistant_and_link'
    add_index :jivo_documents, :status
  end
end
