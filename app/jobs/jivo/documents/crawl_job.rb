class Jivo::Documents::CrawlJob < ApplicationJob
  queue_as :default

  def perform(document)
    return if document.blank? || document.external_link.blank?

    result = Jivo::Tools::SimplePageCrawlService.new(url: document.external_link).perform

    document.update!(
      name: document.name.presence || result[:title].presence || document.external_link,
      content: result[:content].to_s,
      metadata: document.metadata.merge('description' => result[:description])
    )

    if document.content.present?
      Jivo::Documents::ResponseBuilderJob.perform_later(document)
    else
      document.update!(status: :available)
    end
  rescue StandardError => e
    Rails.logger.error "[JIVO] CrawlJob failed for document #{document&.id}: #{e.message}"
    ChatwootExceptionTracker.new(e, account: document&.account).capture_exception
    document&.update(status: :available)
  end
end
