class AddCostMicrosToJivoAiUsages < ActiveRecord::Migration[7.1]
  def change
    add_column :jivo_ai_usages, :cost_micros, :bigint, null: false, default: 0
  end
end
