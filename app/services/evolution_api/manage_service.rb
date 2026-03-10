class EvolutionApi::ManageService
  def initialize
    @api_url = InstallationConfig.find_by(name: 'EVOLUTION_API_URL')&.value.presence || 'http://evolution-api:8080'
    @api_key = InstallationConfig.find_by(name: 'EVOLUTION_API_KEY')&.value.presence || ''
  end

  def create_instance(instance_name, phone_number, groups_ignore: false)
    make_request(:post, '/instance/create', {
      instanceName: instance_name,
      number: phone_number,
      qrcode: true,
      integration: 'WHATSAPP-BAILEYS',
      groupsIgnore: groups_ignore
    })
  end

  def get_qrcode(instance_name)
    make_request(:get, "/instance/connect/#{encode(instance_name)}")
  end

  def connection_state(instance_name)
    make_request(:get, "/instance/connectionState/#{encode(instance_name)}")
  end

  def configure_chatwoot(instance_name, params)
    make_request(:post, "/chatwoot/set/#{encode(instance_name)}", params)
  end

  def delete_instance(instance_name)
    make_request(:delete, "/instance/delete/#{encode(instance_name)}")
  end

  private

  def encode(name)
    ERB::Util.url_encode(name)
  end

  def make_request(method, path, body = nil)
    uri = URI.parse("#{@api_url}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 10
    http.read_timeout = 30

    request = build_request(method, uri, body)
    response = http.request(request)

    handle_response(response)
  end

  def build_request(method, uri, body)
    request = case method
              when :get then Net::HTTP::Get.new(uri)
              when :post then Net::HTTP::Post.new(uri)
              when :delete then Net::HTTP::Delete.new(uri)
              end

    request['Content-Type'] = 'application/json'
    request['apikey'] = @api_key
    request.body = body.to_json if body.present?
    request
  end

  def handle_response(response)
    parsed = JSON.parse(response.body)

    unless response.is_a?(Net::HTTPSuccess)
      error_message = parsed['response']&.dig('message')&.join(', ') || parsed['message'] || 'Unknown error'
      raise StandardError, error_message
    end

    parsed
  end
end
