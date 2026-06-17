require 'net/http'

class Jivo::Llm::ContactAttributesService
  OPENAI_API_URL = 'https://api.openai.com/v1/chat/completions'.freeze
  REQUEST_TIMEOUT = 45
  SUPPORTED_ATTRIBUTES = %w[name email phone_number].freeze

  pattr_initialize [:assistant!, :conversation!]

  def generate
    return [] if missing_attributes.empty?

    raise 'OpenAI API key not configured for assistant' if assistant.effective_openai_api_key.blank?

    response = call_openai
    parse_response(response.dig('choices', 0, 'message', 'content'))
  rescue StandardError => e
    Rails.logger.error "[JIVO] ContactAttributesService error for conversation #{conversation.id}: #{e.message}"
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    []
  end

  private

  def missing_attributes
    @missing_attributes ||= SUPPORTED_ATTRIBUTES.select { |attribute| attribute_missing?(attribute) }
  end

  def attribute_missing?(attribute)
    return name_missing? if attribute == 'name'

    conversation.contact.public_send(attribute).blank?
  end

  def name_missing?
    contact = conversation.contact
    contact.name.blank? || contact.name == contact.phone_number || contact.name == contact.email || contact.name.to_s.end_with?('@s.whatsapp.net')
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
        { role: 'user', content: content }
      ],
      response_format: { type: 'json_object' },
      temperature: 0
    }
  end

  def system_prompt
    <<~PROMPT
      You extract missing contact profile attributes from a customer support conversation.
      Only return attributes explicitly provided by the customer in the conversation.
      Only extract these missing attributes: #{missing_attributes.join(', ')}.
      Do not infer, guess, translate, correct, or invent values.
      For phone_number, return an international E.164 value when the conversation provides enough information; otherwise omit it.
      For name, only return a human name when the customer clearly identifies themselves.
      Return JSON only in this exact shape: {"attributes":[{"attribute":"email","value":"customer@example.com"}]}.
      If nothing is confidently available, return {"attributes":[]}.
    PROMPT
  end

  def content
    "# Contact\n\n#{conversation.contact.to_llm_text}\n\n# Conversation\n\n#{conversation.to_llm_text}"
  end

  def parse_response(response)
    return [] if response.blank?

    JSON.parse(response.strip).fetch('attributes', []).filter_map do |item|
      attribute = item['attribute'].to_s.strip
      value = item['value'].to_s.strip
      next if attribute.blank? || value.blank?
      next unless missing_attributes.include?(attribute)

      { 'attribute' => attribute, 'value' => value }
    end
  rescue JSON::ParserError => e
    Rails.logger.error "[JIVO] ContactAttributesService JSON parse error: #{e.message}"
    []
  end
end
