class Jivo::Llm::UpdateEmbeddingJob < ApplicationJob
  queue_as :low

  retry_on Net::ReadTimeout, attempts: 3, wait: 5.seconds

  def perform(record, content)
    return if record.blank? || content.blank?

    assistant = record.jivo_assistant
    return if assistant.blank? || assistant.effective_openai_api_key.blank?

    embedding = Jivo::Llm::EmbeddingService.new(assistant: assistant).get_embedding(content)
    record.update_column(:embedding, embedding) if embedding.present?
  rescue StandardError => e
    Rails.logger.error "[JIVO] UpdateEmbeddingJob error for #{record&.class}/#{record&.id}: #{e.message}"
    ChatwootExceptionTracker.new(e).capture_exception
  end
end
