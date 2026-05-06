class Jivo::Knowledge::FaqContextService
  DEFAULT_MAX_MESSAGES = 4

  def initialize(assistant:, conversation:, max_messages: DEFAULT_MAX_MESSAGES)
    @assistant = assistant
    @conversation = conversation
    @max_messages = max_messages
  end

  def fetch
    return [] if conversation.blank?
    return [] unless assistant.responses.approved.exists?

    query = aggregated_query
    return [] if query.blank?

    JivoAssistantResponse.search(query, jivo_assistant: assistant).to_a
  rescue StandardError => e
    Rails.logger.warn "[JIVO] FaqContextService failed for conversation #{conversation&.id}: #{e.message}"
    []
  end

  private

  attr_reader :assistant, :conversation, :max_messages

  def aggregated_query
    conversation
      .messages
      .where(message_type: :incoming, private: false)
      .order(created_at: :desc)
      .limit(max_messages)
      .pluck(:content)
      .compact
      .map { |content| content.to_s.strip }
      .reject(&:blank?)
      .reverse
      .join("\n")
  end
end
