class Jivo::Documents::PdfIngestJob < ApplicationJob
  queue_as :default

  def perform(document)
    return if document.blank? || !document.pdf?

    extract_and_persist(document)
    upload_to_openai(document)

    if document.content.present? || document.openai_file_id.present?
      Jivo::Documents::ResponseBuilderJob.perform_later(document)
    else
      document.update!(status: :available)
    end
  rescue StandardError => e
    Rails.logger.error "[JIVO] PdfIngestJob failed for document #{document&.id}: #{e.message}"
    ChatwootExceptionTracker.new(e, account: document&.account).capture_exception
    document&.update_columns(status: JivoDocument.statuses[:available]) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def extract_and_persist(document)
    text = Jivo::Documents::PdfTextExtractor.new(document: document).perform
    document.update!(
      name: document.name.presence || document.file.filename.to_s,
      content: text,
      metadata: document.metadata.merge('source_type' => 'pdf', 'pages' => page_count(document))
    )
  end

  def upload_to_openai(document)
    return if document.jivo_assistant.effective_openai_api_key.blank?

    Jivo::Documents::PdfUploadService.new(document: document).perform
  rescue StandardError => e
    Rails.logger.error "[JIVO] OpenAI PDF upload failed for document #{document.id}: #{e.message}"
    document.update!(
      metadata: document.metadata.merge(
        'openai_file_upload_failed' => true,
        'openai_file_upload_error' => e.message
      )
    )
  end

  def page_count(document)
    document.file.blob.open { |file| PDF::Reader.new(file).page_count }
  rescue StandardError
    nil
  end
end
