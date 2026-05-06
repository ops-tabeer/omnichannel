class Jivo::ConversationHandlerService
  OPENAI_API_URL = 'https://api.openai.com/v1/chat/completions'.freeze
  HANDOFF_SIGNAL = 'conversation_handoff'.freeze
  REQUEST_TIMEOUT = 30
  MAX_MESSAGE_LENGTH = 10_000

  pattr_initialize [:conversation!, :assistant!]

  def perform
    return Jivo::ConversationV2HandlerService.new(conversation: conversation, assistant: assistant).perform if assistant.feature_v2_agent_enabled?

    @knowledge_context = retrieve_knowledge_context
    raw_response = call_openai(build_messages)
    process_response(raw_response)
  rescue StandardError => e
    Rails.logger.error "[JIVO] ConversationHandlerService error for conversation #{conversation.id}: #{e.message}"
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    perform_handoff(assistant.handoff_message_text)
  end

  private

  delegate :account, :inbox, to: :conversation

  def retrieve_knowledge_context
    Jivo::Knowledge::FaqContextService.new(
      assistant: assistant,
      conversation: conversation
    ).fetch
  end

  def build_messages
    history = conversation.messages
                          .where(message_type: [:incoming, :outgoing])
                          .where(private: false)
                          .order(:created_at)
                          .map { |msg| message_payload(msg) }
                          .reject { |m| m[:content].blank? }

    [system_message] + history
  end

  def message_payload(msg)
    {
      role: msg.message_type == 'incoming' ? 'user' : 'assistant',
      content: build_content(msg)
    }
  end

  def build_content(msg)
    content = Jivo::OpenaiMessageBuilderService.new(message: msg, assistant: assistant).generate_content

    if content.is_a?(String)
      content.strip[0, MAX_MESSAGE_LENGTH]
    else
      content
    end
  end

  def system_message
    { role: 'system', content: system_prompt_text }
  end

  def system_prompt_text
    Jivo::Prompts::V1ConversationPrompt.new(
      assistant: assistant,
      knowledge_context: @knowledge_context,
      contact_notes: recent_contact_notes
    ).render
  end

  def recent_contact_notes
    conversation.contact.notes.order(created_at: :desc).limit(10).pluck(:content).reject(&:blank?)
  end

  def call_openai(messages)
    raise 'OpenAI API key not configured' if assistant.openai_api_key.blank?

    uri = URI.parse(OPENAI_API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = REQUEST_TIMEOUT

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{assistant.openai_api_key}"
    request.body = {
      model: assistant.model,
      messages: messages,
      response_format: { type: 'json_object' },
      temperature: assistant.temperature_value
    }.to_json

    response = http.request(request)
    raise "OpenAI API error #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def process_response(raw_response)
    parsed = parse_ai_response(raw_response)
    reply = parsed['response'].to_s.strip

    if reply == HANDOFF_SIGNAL
      perform_handoff(assistant.handoff_message_text)
    elsif reply.present?
      create_outgoing_message(reply)
    else
      raise 'JIVO returned blank response'
    end
  end

  def parse_ai_response(raw_response)
    content = raw_response.dig('choices', 0, 'message', 'content')
    raise 'Empty response from OpenAI' if content.blank?

    JSON.parse(content)
  rescue JSON::ParserError => e
    raise "Failed to parse OpenAI JSON response: #{e.message}"
  end

  def create_outgoing_message(content)
    conversation.messages.create!(
      message_type: :outgoing,
      account_id: account.id,
      inbox_id: inbox.id,
      sender: assistant,
      content: content,
      private: false
    )
  end

  def perform_handoff(message_content)
    return unless conversation.pending?

    ActiveRecord::Base.transaction do
      conversation.messages.create!(
        message_type: :outgoing,
        account_id: account.id,
        inbox_id: inbox.id,
        content: message_content,
        private: false
      )
      conversation.bot_handoff!
    end
  end
end
