class Jivo::Knowledge::FaqContextService
  DEFAULT_MAX_MESSAGES = 4

  def initialize(assistant:, conversation: nil, message_history: nil, max_messages: DEFAULT_MAX_MESSAGES)
    @assistant = assistant
    @conversation = conversation
    @message_history = message_history
    @max_messages = max_messages
  end

  def fetch
    return [] unless assistant.responses.approved.exists?

    query = aggregated_query
    return [] if query.blank?

    JivoAssistantResponse.search(query, jivo_assistant: assistant).to_a
  rescue StandardError => e
    Rails.logger.warn "[JIVO] FaqContextService failed for conversation #{conversation&.id}: #{e.message}"
    []
  end

  private

  attr_reader :assistant, :conversation, :message_history, :max_messages

  def aggregated_query
    return query_from_message_history if message_history.present?
    return query_from_conversation if conversation.present?

    ''
  end

  def query_from_conversation
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

  def query_from_message_history
    message_history
      .select { |msg| msg[:role].to_s == 'user' }
      .last(max_messages)
      .map { |msg| msg[:content].to_s.strip }
      .reject(&:blank?)
      .join("\n")
  end
end
