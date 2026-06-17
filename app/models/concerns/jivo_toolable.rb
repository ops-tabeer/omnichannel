module JivoToolable
  extend ActiveSupport::Concern

  def tool(assistant)
    custom_tool_record = self
    class_name = custom_tool_record.slug.underscore.camelize

    tool_class = Class.new(Jivo::Tools::HttpTool) do
      description custom_tool_record.description

      custom_tool_record.param_schema.each do |param_def|
        param param_def['name'].to_sym,
              type: param_def['type'],
              desc: param_def['description'],
              required: param_def.fetch('required', true)
      end
    end

    Jivo::Tools.send(:remove_const, class_name) if Jivo::Tools.const_defined?(class_name, false)
    Jivo::Tools.const_set(class_name, tool_class)

    tool_class.new(assistant, self)
  end

  def build_request_url(params)
    return endpoint_url if endpoint_url.blank? || endpoint_url.exclude?('{{')

    render_template(endpoint_url, params)
  end

  def build_request_body(params)
    return nil if request_template.blank?

    render_template(request_template, params)
  end

  def build_auth_headers
    return {} if auth_none?

    case auth_type
    when 'bearer'
      { 'Authorization' => "Bearer #{auth_config['token']}" }
    when 'api_key'
      auth_config['location'] == 'header' ? { auth_config['name'] => auth_config['key'] } : {}
    else
      {}
    end
  end

  def build_basic_auth_credentials
    return nil unless auth_type == 'basic'

    [auth_config['username'], auth_config['password']]
  end

  def build_metadata_headers(state)
    {}.tap do |headers|
      add_base_headers(headers, state)
      add_conversation_headers(headers, state[:conversation]) if state[:conversation]
      add_contact_headers(headers, state[:contact]) if state[:contact]
    end
  end

  def format_response(raw_response_body)
    return raw_response_body if response_template.blank?

    response_data = parse_response_body(raw_response_body)
    render_template(response_template, { 'response' => response_data, 'r' => response_data })
  end

  private

  def add_base_headers(headers, state)
    headers['X-Jivo-Account-Id'] = state[:account_id].to_s if state[:account_id]
    headers['X-Jivo-Assistant-Id'] = state[:assistant_id].to_s if state[:assistant_id]
    headers['X-Jivo-Tool-Slug'] = slug if slug.present?
  end

  def add_conversation_headers(headers, conversation)
    headers['X-Jivo-Conversation-Id'] = conversation[:id].to_s if conversation[:id]
    headers['X-Jivo-Conversation-Display-Id'] = conversation[:display_id].to_s if conversation[:display_id]
  end

  def add_contact_headers(headers, contact)
    headers['X-Jivo-Contact-Id'] = contact[:id].to_s if contact[:id]
    headers['X-Jivo-Contact-Email'] = contact[:email].to_s if contact[:email].present?
    headers['X-Jivo-Contact-Phone'] = contact[:phone_number].to_s if contact[:phone_number].present?
  end

  def render_template(template, context)
    liquid_template = Liquid::Template.parse(template, error_mode: :strict)
    liquid_template.render(context.deep_stringify_keys, registers: {}, strict_variables: true, strict_filters: true)
  rescue Liquid::SyntaxError, Liquid::UndefinedVariable, Liquid::UndefinedFilter => e
    Rails.logger.error("Liquid template error: #{e.message}")
    raise "Template rendering failed: #{e.message}"
  end

  def parse_response_body(body)
    JSON.parse(body)
  rescue JSON::ParserError
    body
  end
end
