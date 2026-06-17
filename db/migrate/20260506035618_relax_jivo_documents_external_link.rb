class RelaxJivoDocumentsExternalLink < ActiveRecord::Migration[7.1]
  def change
    change_column_null :jivo_documents, :external_link, true
  end
end
