class AddTokenColumnsToJivoAiUsages < ActiveRecord::Migration[7.1]
  def change
    add_column :jivo_ai_usages, :input_tokens, :bigint, null: false, default: 0
    add_column :jivo_ai_usages, :output_tokens, :bigint, null: false, default: 0
  end
end
