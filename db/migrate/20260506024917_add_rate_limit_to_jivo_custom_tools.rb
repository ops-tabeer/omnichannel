class AddRateLimitToJivoCustomTools < ActiveRecord::Migration[7.1]
  def change
    add_column :jivo_custom_tools, :rate_limit_per_minute, :integer
  end
end
