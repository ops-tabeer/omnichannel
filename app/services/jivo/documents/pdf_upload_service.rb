class Jivo::Documents::PdfUploadService
  pattr_initialize [:document!]

  def perform
    return document.openai_file_id if document.openai_file_id.present?

    file_id = upload_pdf
    document.store_openai_file_id(file_id) if file_id.present?
    file_id
  end

  private

  def upload_pdf
    document.file.blob.open do |blob_file|
      response = client.files.upload(
        parameters: {
          file: blob_file,
          purpose: 'assistants'
        }
      )
      response['id']
    end
  end

  def client
    @client ||= OpenAI::Client.new(
      access_token: document.jivo_assistant.openai_api_key,
      log_errors: Rails.env.development?
    )
  end
end
