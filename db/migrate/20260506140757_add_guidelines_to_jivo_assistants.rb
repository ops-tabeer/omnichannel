class AddGuidelinesToJivoAssistants < ActiveRecord::Migration[7.1]
  def change
    add_column :jivo_assistants, :response_guidelines, :jsonb, default: []
    add_column :jivo_assistants, :guardrails, :jsonb, default: []
  end
end
