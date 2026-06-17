class Jivo::Documents::ResponseBuilderJob < ApplicationJob
  queue_as :default

  CHUNK_SIZE = Jivo::Llm::FaqGeneratorService::MAX_CONTENT_LENGTH

  def perform(document)
    return unless processable_document?(document)

    assistant = document.jivo_assistant
    return unless processable_assistant?(assistant)

    document.jivo_assistant_responses.destroy_all
    faqs = generate_faqs(document, assistant)
    create_responses(document, assistant, dedupe(faqs))
    document.update!(status: :available)
  rescue StandardError => e
    Rails.logger.error "[JIVO] ResponseBuilderJob failed for document #{document&.id}: #{e.message}"
    ChatwootExceptionTracker.new(e, account: document&.account).capture_exception
    document&.update_columns(status: JivoDocument.statuses[:available]) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def processable_document?(document)
    return false if document.blank?

    document.content.present? || (document.pdf? && document.openai_file_id.present?)
  end

  def processable_assistant?(assistant)
    assistant.present? && assistant.effective_openai_api_key.present?
  end

  def generate_faqs(document, assistant)
    faqs = if document.pdf? && document.openai_file_id.present?
             generate_paginated_pdf_faqs(document)
           else
             generate_faqs_for_chunks(assistant, document.content)
           end

    audit_faqs = audit_missing_faqs(assistant, document.content, faqs)
    store_audit_metadata(document, audit_faqs.size)
    dedupe(faqs + audit_faqs)
  end

  def generate_paginated_pdf_faqs(document)
    service = Jivo::Documents::PaginatedFaqGeneratorService.new(document: document)
    faqs = service.generate
    raise 'Paginated PDF generation returned no FAQs' if faqs.blank?

    store_paginated_metadata(document, service, faqs.size)
    faqs
  rescue StandardError => e
    Rails.logger.error "[JIVO] Paginated PDF FAQ generation failed for document #{document.id}: #{e.message}"
    document.update!(
      metadata: document.metadata.merge(
        'pdf_generation_fallback' => 'local_text_chunks',
        'pdf_generation_error' => e.message
      )
    )
    generate_faqs_for_chunks(document.jivo_assistant, document.content)
  end

  def store_paginated_metadata(document, service, faqs_count)
    document.update!(
      metadata: document.metadata.merge(
        'faq_generation' => {
          'method' => 'openai_file_paginated_with_audit',
          'pages_processed' => service.total_pages_processed,
          'iterations' => service.iterations_completed,
          'faqs_generated' => faqs_count,
          'timestamp' => Time.current.iso8601
        }
      )
    )
  end

  def audit_missing_faqs(assistant, content, faqs)
    Jivo::Documents::FaqCoverageAuditService.new(
      assistant: assistant,
      content: content,
      faqs: faqs
    ).perform
  end

  def store_audit_metadata(document, audit_faqs_count)
    document.update!(
      metadata: document.metadata.merge(
        'faq_coverage_audit' => {
          'faqs_added' => audit_faqs_count,
          'timestamp' => Time.current.iso8601
        }
      )
    )
  end

  def generate_faqs_for_chunks(assistant, content)
    chunks_for(content).flat_map do |chunk|
      Jivo::Llm::FaqGeneratorService.new(assistant: assistant, content: chunk).generate
    end
  end

  def chunks_for(content)
    text = content.to_s
    return [text] if text.length <= CHUNK_SIZE

    text.chars.each_slice(CHUNK_SIZE).map(&:join)
  end

  def dedupe(faqs)
    faqs
      .select { |faq| faq['question'].to_s.strip.present? && faq['answer'].to_s.strip.present? }
      .uniq { |faq| faq['question'].to_s.strip.downcase }
  end

  def create_responses(document, assistant, faqs)
    faqs.each do |faq|
      JivoAssistantResponse.create!(
        jivo_assistant: assistant,
        documentable: document,
        question: faq['question'].to_s.strip,
        answer: faq['answer'].to_s.strip,
        status: :pending
      )
    end
  end
end
