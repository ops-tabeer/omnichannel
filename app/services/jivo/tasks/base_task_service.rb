class Jivo::Tasks::BaseTaskService
  OPENAI_API_URL = 'https://api.openai.com/v1/chat/completions'.freeze
  REQUEST_TIMEOUT = 90
  MAX_INPUT_LENGTH = 400_000

  def initialize(assistant:, **opts)
    @assistant = assistant
    @opts = opts
  end

  def perform
    raise 'OpenAI API key not configured for assistant' if @assistant.openai_api_key.blank?

    response = call_openai(build_messages)
    build_result(response)
  rescue StandardError => e
    Rails.logger.error "[JIVO][#{self.class.name}] error: #{e.message}"
    ChatwootExceptionTracker.new(e, account: @assistant.account).capture_exception
    { success: false, error: e.message }
  end

  protected

  attr_reader :assistant, :opts

  # Override in subclasses
  def build_messages
    raise NotImplementedError
  end

  # Override in subclasses to customize parsing
  def build_result(response)
    content = response.dig('choices', 0, 'message', 'content').to_s.strip
    { success: true, message: content }
  end

  def temperature
    0.4
  end

  def use_json_response?
    false
  end

  private

  def call_openai(messages)
    uri = URI.parse(OPENAI_API_URL)
    response = openai_http_client(uri).request(openai_request(uri, messages))
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

  def openai_request(uri, messages)
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{@assistant.openai_api_key}"
    request.body = openai_request_body(messages).to_json
    request
  end

  def openai_request_body(messages)
    body = {
      model: @assistant.model,
      messages: messages,
      temperature: temperature
    }
    body[:response_format] = { type: 'json_object' } if use_json_response?
    body
  end
end
