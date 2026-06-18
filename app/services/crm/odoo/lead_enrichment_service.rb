require 'net/http'

# Extracts structured travel-inquiry fields (inquiry type + nationality/destination
# countries) from the AI handoff note + conversation transcript using the assistant's LLM,
# so the Odoo lead can be auto-classified. Mirrors Jivo::Llm::ContactAttributesService.
# Best-effort: any failure is logged and swallowed (returns {}) so it never blocks lead creation.
class Crm::Odoo::LeadEnrichmentService
  OPENAI_API_URL = 'https://api.openai.com/v1/chat/completions'.freeze
  REQUEST_TIMEOUT = 45

  # Mirrors the crm.lead `inquiry_type` selection in Odoo (key => label). Update if Odoo
  # adds inquiry types. The LLM must pick one of these keys or null.
  INQUIRY_TYPES = {
    'philippine_package' => 'Philippine Package',
    'uae_visa' => 'UAE Visa',
    'visa_change' => 'Visa Change',
    'air_ticket' => 'Air Ticket',
    'holiday_outbound' => 'Holidays Outbound',
    'holiday_inbound' => 'Holiday Inbound',
    'international_visa' => 'International Visa',
    'schengen_visa' => 'Schengen Visa',
    'travel_insurance' => 'Travel Insurance',
    'escape_removal' => 'Escape Removal',
    'general_inquiry' => 'General Inquiry',
    'umrah_inquiry' => 'Umrah Inquiry',
    'student_visa' => 'Student Visa'
  }.freeze

  pattr_initialize [:assistant!, :content!]

  # Returns a hash with any of 'inquiry_type' (key), 'nationality', 'destination'
  # (canonical English country names) that the content clearly supports.
  def extract
    return {} if content.blank? || assistant.effective_openai_api_key.blank?

    response = call_openai
    parse_response(response.dig('choices', 0, 'message', 'content'))
  rescue StandardError => e
    Rails.logger.error "[ODOO] LeadEnrichmentService error: #{e.message}"
    ChatwootExceptionTracker.new(e, account: assistant.account).capture_exception
    {}
  end

  private

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
      You extract travel-inquiry fields from a customer support conversation and the AI assistant's handoff note.
      Only return values explicitly supported by what the customer said. Do not infer, guess, translate, or invent.

      Fields:
      - inquiry_type: choose EXACTLY ONE key whose label best matches the customer's request, or null. Options (key = label):
      #{inquiry_type_options}
      - nationality: the customer's nationality as a canonical English country name (e.g. "India"), or null.
      - destination: the travel destination country as a canonical English country name (e.g. "United Arab Emirates"), or null.

      Return JSON only in this exact shape:
      {"inquiry_type":"uae_visa","nationality":"India","destination":"United Arab Emirates"}
      Use null for any field not clearly present in the conversation.
    PROMPT
  end

  def inquiry_type_options
    INQUIRY_TYPES.map { |key, label| "        #{key} = #{label}" }.join("\n")
  end

  def parse_response(response)
    return {} if response.blank?

    data = JSON.parse(response.strip)
    {
      'inquiry_type' => valid_inquiry_type(data['inquiry_type']),
      'nationality' => data['nationality'].to_s.strip.presence,
      'destination' => data['destination'].to_s.strip.presence
    }.compact
  rescue JSON::ParserError => e
    Rails.logger.error "[ODOO] LeadEnrichmentService JSON parse error: #{e.message}"
    {}
  end

  def valid_inquiry_type(value)
    key = value.to_s.strip
    key if INQUIRY_TYPES.key?(key)
  end
end
