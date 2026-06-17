require 'agents'

class Jivo::Tools::HttpTool < Agents::Tool
  MAX_RESPONSE_SIZE = 1.megabyte

  def initialize(assistant, custom_tool)
    @assistant = assistant
    @custom_tool = custom_tool
    super()
  end

  def active?
    @custom_tool.enabled?
  end

  def perform(tool_context, **params)
    Jivo::Tools::RateLimiter.new(custom_tool: @custom_tool).check!

    url = @custom_tool.build_request_url(params)
    body = @custom_tool.build_request_body(params)

    response = execute_http_request(url, body, tool_context)
    @custom_tool.format_response(response.body)
  rescue Jivo::Tools::RateLimiter::RateLimitExceeded => e
    Rails.logger.warn("Jivo::Tools::HttpTool rate limit hit for #{@custom_tool.slug}: #{e.message}")
    "Rate limit reached for #{@custom_tool.slug}. Please try again in a minute."
  rescue StandardError => e
    Rails.logger.error("Jivo::Tools::HttpTool execution error for #{@custom_tool.slug}: #{e.class} - #{e.message}")
    'An error occurred while executing the request'
  end

  private

  def execute_http_request(url, body, tool_context)
    uri = URI.parse(url)
    dns_validator = Jivo::Tools::DnsValidator.new(uri.host).validate!

    http = build_http_client(uri)

    request = build_http_request(uri, body)
    apply_authentication(request)
    apply_metadata_headers(request, tool_context)

    dns_validator.reverify!
    response = http.request(request)
    raise "HTTP request failed with status #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    validate_response!(response)
    response
  end

  def build_http_client(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 30
    http.open_timeout = 10
    http.max_retries = 0
    http
  end

  def validate_response!(response)
    content_length = response['content-length']&.to_i
    if content_length && content_length > MAX_RESPONSE_SIZE
      raise "Response size #{content_length} bytes exceeds maximum allowed #{MAX_RESPONSE_SIZE} bytes"
    end

    return unless response.body && response.body.bytesize > MAX_RESPONSE_SIZE

    raise "Response body size #{response.body.bytesize} bytes exceeds maximum allowed #{MAX_RESPONSE_SIZE} bytes"
  end

  def build_http_request(uri, body)
    if @custom_tool.http_method == 'POST'
      request = Net::HTTP::Post.new(uri.request_uri)
      if body
        request.body = body
        request['Content-Type'] = 'application/json'
      end
    else
      request = Net::HTTP::Get.new(uri.request_uri)
    end
    request
  end

  def apply_authentication(request)
    @custom_tool.build_auth_headers.each { |k, v| request[k] = v }

    credentials = @custom_tool.build_basic_auth_credentials
    request.basic_auth(*credentials) if credentials
  end

  def apply_metadata_headers(request, tool_context)
    state = tool_context&.state || {}
    @custom_tool.build_metadata_headers(state).each { |k, v| request[k] = v }
  end
end
