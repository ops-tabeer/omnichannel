class Jivo::Documents::CrawlJob < ApplicationJob
  include Jivo::FirecrawlHelper

  queue_as :default

  def perform(document)
    return if document.blank? || document.external_link.blank?

    if firecrawl_configured?
      perform_firecrawl(document)
    else
      perform_simple_crawl(document)
    end
  rescue StandardError => e
    Rails.logger.error "[JIVO] CrawlJob failed for document #{document&.id}: #{e.message}"
    ChatwootExceptionTracker.new(e, account: document&.account).capture_exception
    document&.update_columns(status: JivoDocument.statuses[:available]) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def firecrawl_configured?
    InstallationConfig.find_by(name: 'JIVO_FIRECRAWL_API_KEY')&.value.present?
  end

  def perform_simple_crawl(document)
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
  end

  def perform_firecrawl(document)
    Jivo::Tools::FirecrawlService.new.perform(
      document.external_link,
      firecrawl_webhook_url(document),
      10
    )
  end

  def firecrawl_webhook_url(document)
    base = Rails.application.routes.url_helpers.webhooks_jivo_firecrawl_url
    token = generate_jivo_firecrawl_token(document.jivo_assistant_id, document.account_id)
    "#{base}?assistant_id=#{document.jivo_assistant_id}&token=#{token}"
  end
end
