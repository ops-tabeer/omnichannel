class Jivo::Documents::ResponseBuilderJob < ApplicationJob
  queue_as :default

  def perform(document)
    return if document.blank? || document.content.blank?

    assistant = document.jivo_assistant
    return if assistant.blank? || assistant.openai_api_key.blank?

    faqs = Jivo::Llm::FaqGeneratorService.new(
      assistant: assistant,
      content: document.content
    ).generate

    create_responses(document, assistant, faqs)
    document.update!(status: :available)
  rescue StandardError => e
    Rails.logger.error "[JIVO] ResponseBuilderJob failed for document #{document&.id}: #{e.message}"
    ChatwootExceptionTracker.new(e, account: document&.account).capture_exception
    document&.update(status: :available)
  end

  private

  def create_responses(document, assistant, faqs)
    faqs.each do |faq|
      JivoAssistantResponse.create!(
        jivo_assistant: assistant,
        documentable: document,
        question: faq['question'].to_s.strip,
        answer: faq['answer'].to_s.strip,
        status: :approved
      )
    end
  end
end
