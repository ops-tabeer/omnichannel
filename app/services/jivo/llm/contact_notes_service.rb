require 'net/http'

class Jivo::Llm::ContactNotesService
  OPENAI_API_URL = 'https://api.openai.com/v1/chat/completions'.freeze
  REQUEST_TIMEOUT = 90

  pattr_initialize [:assistant!, :conversation!]

  def generate_and_update_notes
    generate_notes.each do |note|
      next if recent_duplicate_note?(note)

      conversation.contact.notes.create!(content: note)
    end
  end

  private

  def recent_duplicate_note?(content)
    conversation.contact.notes.exists?(content: content, created_at: 7.days.ago..)
  end

  def generate_notes
    raise 'OpenAI API key not configured for assistant' if assistant.openai_api_key.blank?

    response = call_openai
    parse_response(response.dig('choices', 0, 'message', 'content'))
  rescue StandardError => e
    Rails.logger.error "[JIVO] ContactNotesService error for conversation #{conversation.id}: #{e.message}"
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    []
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
    request['Authorization'] = "Bearer #{assistant.openai_api_key}"
    request.body = request_body.to_json
    request
  end

  def request_body
    {
      model: assistant.model,
      messages: [
        { role: 'system', content: system_prompt },
        { role: 'user', content: content }
      ],
      response_format: { type: 'json_object' },
      temperature: assistant.temperature_value
    }
  end

  def system_prompt
    <<~PROMPT
      You generate concise memory notes for a customer support contact profile.
      Read the contact details and resolved conversation, then extract durable facts that will help future agents.
      Include preferences, confirmed needs, recurring issues, important constraints, or useful context.
      Do not include temporary status updates, greetings, duplicate information, or speculation.
      Return JSON only in this exact shape: {"notes":["note 1","note 2"]}.
      Generate 1-3 notes in #{conversation.account.locale_english_name}.
    PROMPT
  end

  def content
    "# Contact\n\n#{conversation.contact.to_llm_text}\n\n# Conversation\n\n#{conversation.to_llm_text}"
  end

  def parse_response(response)
    return [] if response.blank?

    JSON.parse(response.strip).fetch('notes', []).map(&:to_s).map(&:strip).reject(&:blank?)
  rescue JSON::ParserError => e
    Rails.logger.error "[JIVO] ContactNotesService JSON parse error: #{e.message}"
    []
  end
end
