require 'net/http'

class Jivo::Llm::ConversationFaqService
  OPENAI_API_URL = 'https://api.openai.com/v1/chat/completions'.freeze
  REQUEST_TIMEOUT = 90
  DUPLICATE_DISTANCE_THRESHOLD = 0.1

  pattr_initialize [:assistant!, :conversation!, :force]

  def generate_and_deduplicate
    return [] if !force && no_human_interaction?

    faqs = generate
    return [] if faqs.blank?

    save_new_faqs(unique_faqs(faqs))
  end

  private

  def no_human_interaction?
    conversation.first_reply_created_at.blank?
  end

  def generate
    raise 'OpenAI API key not configured for assistant' if assistant.effective_openai_api_key.blank?

    response = call_openai
    parse_response(response.dig('choices', 0, 'message', 'content'))
  rescue StandardError => e
    Rails.logger.error "[JIVO] ConversationFaqService error for conversation #{conversation.id}: #{e.message}"
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    []
  end

  def unique_faqs(faqs)
    faqs.select do |faq|
      question = faq['question'].to_s.strip
      answer = faq['answer'].to_s.strip
      question.present? && answer.present? && !duplicate_faq?(question, answer)
    end
  end

  def duplicate_faq?(question, answer)
    embedding = Jivo::Llm::EmbeddingService.new(assistant: assistant).get_embedding("#{question}: #{answer}")
    return false if embedding.blank?

    assistant.responses
             .approved
             .nearest_neighbors(:embedding, embedding, distance: 'cosine')
             .limit(5)
             .any? { |record| record.neighbor_distance.to_f < DUPLICATE_DISTANCE_THRESHOLD }
  rescue StandardError => e
    Rails.logger.warn "[JIVO] Conversation FAQ dedupe failed: #{e.message}"
    false
  end

  def save_new_faqs(faqs)
    faqs.map do |faq|
      assistant.responses.create!(
        question: faq['question'].to_s.strip,
        answer: faq['answer'].to_s.strip,
        status: :pending,
        documentable: nil
      )
    end
  end

  def call_openai
    uri = URI.parse(OPENAI_API_URL)
    response = openai_http_client(uri).request(openai_request(uri))
    raise "OpenAI API error #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def openai_http_client(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = REQUEST_TIMEOUT
    http
  end

  def openai_request(uri)
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{assistant.effective_openai_api_key}"
    request.body = request_body.to_json
    request
  end

  def request_body
    {
      model: assistant.model,
      messages: [
        { role: 'system', content: system_prompt },
        { role: 'user', content: conversation_text }
      ],
      response_format: { type: 'json_object' },
      temperature: assistant.temperature_value
    }
  end

  def system_prompt
    <<~PROMPT
      You are a support knowledge manager converting resolved support conversations into reusable FAQs.
      Extract only durable, general customer questions and accurate answers from the conversation.
      Do not include private customer details, temporary order/status details, greetings, or agent process notes.
      Return JSON only in this exact shape: {"faqs":[{"question":"...","answer":"..."}]}.
      Generate 1-5 FAQs in #{conversation.account.locale_english_name}.
    PROMPT
  end

  def conversation_text
    messages = conversation.messages
                           .where(message_type: [:incoming, :outgoing], private: false)
                           .where.not(sender_type: %w[JivoAssistant AgentBot])
                           .order(:created_at)

    messages.map do |message|
      role = message.incoming? ? 'Customer' : 'Agent'
      "#{role}: #{message.content_for_llm}"
    end.join("\n")
  end

  def parse_response(response)
    return [] if response.blank?

    JSON.parse(response.strip).fetch('faqs', [])
  rescue JSON::ParserError => e
    Rails.logger.error "[JIVO] ConversationFaqService JSON parse error: #{e.message}"
    []
  end
end
