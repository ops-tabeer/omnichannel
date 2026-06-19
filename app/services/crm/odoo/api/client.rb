class Crm::Odoo::Api::Client
  include HTTParty

  class ApiError < StandardError; end

  def initialize(url:, db:, login:, api_key:)
    @url = url.to_s.chomp('/')
    @db = db
    @login = login
    @api_key = api_key
  end

  # Authenticates the bot user and memoizes the uid. Returns the Odoo user id.
  def authenticate
    @uid ||= call('common', 'authenticate', [@db, @login, @api_key, {}])
    raise ApiError, 'Odoo authentication failed - check url, db, login and api key' if @uid.blank?

    @uid
  end

  # Runs an ORM method on an Odoo model (e.g. crm.lead, res.partner, res.users).
  def execute_kw(model, method, args = [], kwargs = {})
    call('object', 'execute_kw', [@db, authenticate, @api_key, model, method, args, kwargs])
  end

  private

  def call(service, method, args)
    response = self.class.post(
      "#{@url}/jsonrpc",
      headers: { 'Content-Type' => 'application/json' },
      body: { jsonrpc: '2.0', method: 'call', id: SecureRandom.uuid,
              params: { service: service, method: method, args: args } }.to_json,
      timeout: 20
    )
    parse(response)
  end

  def parse(response)
    raise ApiError, "Odoo HTTP error: #{response.code}" unless response.success?

    body = response.parsed_response
    if body.is_a?(Hash) && body['error']
      message = body.dig('error', 'data', 'message').presence || body['error'].to_s
      raise ApiError, "Odoo JSON-RPC error: #{message}"
    end

    body.is_a?(Hash) ? body['result'] : body
  end
end
