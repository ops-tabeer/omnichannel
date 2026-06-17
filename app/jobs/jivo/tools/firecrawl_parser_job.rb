class Jivo::Tools::FirecrawlParserJob < ApplicationJob
  queue_as :default

  def perform(assistant_id:, payload:)
    assistant = JivoAssistant.find(assistant_id)
    metadata = payload[:metadata] || {}
    canonical_url = normalize_link(metadata['url'])
    return if canonical_url.blank?

    document = assistant.documents.find_or_initialize_by(external_link: canonical_url)
    document.update!(
      external_link: canonical_url,
      content: payload[:markdown].to_s,
      name: metadata['title'].presence || canonical_url
    )

    if document.content.present?
      Jivo::Documents::ResponseBuilderJob.perform_later(document)
    else
      document.update!(status: :available)
    end
  rescue StandardError => e
    Rails.logger.error "[JIVO] FirecrawlParserJob failed: #{e.message}"
    ChatwootExceptionTracker.new(e).capture_exception
  end

  private

  def normalize_link(raw_url)
    raw_url.to_s.delete_suffix('/')
  end
end
