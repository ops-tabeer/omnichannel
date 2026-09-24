class AddAssistantIdsToJivoCustomTools < ActiveRecord::Migration[7.1]
  def change
    # Empty = available to every assistant in the account (the pre-existing behaviour).
    add_column :jivo_custom_tools, :assistant_ids, :bigint, array: true, default: [], null: false
  end
end
