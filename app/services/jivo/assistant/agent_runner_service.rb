require 'agents'
require 'agents/instrumentation'

class Jivo::Assistant::AgentRunnerService
  include Integrations::LlmInstrumentationConstants

  CONVERSATION_STATE_ATTRIBUTES = %i[
    id display_id inbox_id contact_id status priority
    label_list custom_attributes additional_attributes
  ].freeze

  CONTACT_STATE_ATTRIBUTES = %i[
    id name email phone_number identifier contact_type
    custom_attributes additional_attributes
  ].freeze

  pattr_initialize [:assistant!, :conversation]

  def generate_response(message_history: [])
    Jivo::Runtime::ApiKeyLock.with_assistant_key(assistant) do
      agents = build_and_wire_agents
      current_message, prior_history = split_current_user_message(message_history)
      context = build_context(prior_history)
      last_user_message = message_input(current_message)

      runner = Agents::Runner.with_agents(*agents)
      install_instrumentation(runner)
      result = runner.run(last_user_message, context: context, max_turns: 100)

      process_agent_result(result)
    end
  rescue StandardError => e
    Rails.logger.error "[JIVO V2] AgentRunnerService error: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    ChatwootExceptionTracker.new(e, account: conversation&.account).capture_exception

    error_response(e.message)
  end

  private

  def install_instrumentation(runner)
    return unless ChatwootApp.otel_enabled?

    Agents::Instrumentation.install(
      runner,
      tracer: OpentelemetryConfig.tracer,
      trace_name: 'llm.jivo_v2',
      span_attributes: { ATTR_LANGFUSE_TAGS => ['jivo_v2'].to_json },
      attribute_provider: ->(context_wrapper) { dynamic_trace_attributes(context_wrapper) }
    )
  end

  def dynamic_trace_attributes(context_wrapper)
    state = context_wrapper&.context&.dig(:state) || {}
    conversation_state = state[:conversation] || {}
    {
      ATTR_LANGFUSE_USER_ID => state[:account_id],
      format(ATTR_LANGFUSE_METADATA, 'assistant_id') => state[:assistant_id],
      format(ATTR_LANGFUSE_METADATA, 'conversation_id') => conversation_state[:id],
      format(ATTR_LANGFUSE_METADATA, 'conversation_display_id') => conversation_state[:display_id]
    }.compact.transform_values(&:to_s)
  end

  def build_and_wire_agents
    main_agent = assistant.agent
    scenario_agents = assistant.scenarios.enabled.map(&:agent)

    if scenario_agents.any?
      main_agent.register_handoffs(*scenario_agents)
      scenario_agents.each { |sa| sa.register_handoffs(main_agent) }
    end

    [main_agent] + scenario_agents
  end

  def build_context(message_history)
    history = message_history.map do |msg|
      {
        role: msg[:role].to_sym,
        content: extract_text_from_content(msg[:content])
      }
    end

    {
      session_id: "#{assistant.account_id}_#{conversation&.display_id}",
      conversation_history: history,
      state: build_state
    }
  end

  def build_state
    state = {
      account_id: assistant.account_id,
      assistant_id: assistant.id,
      assistant_config: assistant.config
    }

    if conversation
      state[:conversation] = conversation.attributes.symbolize_keys.slice(*CONVERSATION_STATE_ATTRIBUTES)
      state[:contact] = conversation.contact.attributes.symbolize_keys.slice(*CONTACT_STATE_ATTRIBUTES) if conversation.contact
      state[:preloaded_knowledge] = preloaded_knowledge_payload
    end

    state
  end

  def preloaded_knowledge_payload
    Jivo::Knowledge::FaqContextService.new(assistant: assistant, conversation: conversation).fetch
                                      .map { |faq| { question: faq.question, answer: faq.answer } }
  end

  def extract_text_from_content(content)
    return '' if content.nil?
    return content[:response] || content['response'] || content.to_s if content.is_a?(Hash)
    return content unless content.is_a?(Array)

    [text_parts(content), image_attachment_note(content)].reject(&:blank?).join(' ')
  end

  def split_current_user_message(message_history)
    current_index = message_history.rindex { |msg| msg[:role].to_s == 'user' }
    return [nil, message_history] if current_index.blank?

    current_message = message_history[current_index]
    prior_history = message_history.each_with_index.reject { |_msg, index| index == current_index }.map(&:first)

    [current_message, prior_history]
  end

  def message_input(message)
    content = message && message[:content]
    return extract_text_from_content(content) unless content.is_a?(Array)

    RubyLLM::Content::Raw.new(content)
  end

  def text_parts(content)
    content.select { |part| part[:type] == 'text' }.pluck(:text).join(' ')
  end

  def image_attachment_note(content)
    image_count = content.count { |part| part[:type] == 'image_url' }
    return '' unless image_count.positive?

    "[#{image_count} image attachment#{'s' if image_count > 1}]"
  end

  def process_agent_result(result)
    Rails.logger.info "[JIVO V2] Agent result class=#{result.output.class}, preview=#{result.output.inspect[0, 300]}"
    payload = normalize_output(result.output)
    current_agent = result.context&.dig(:current_agent)
    payload['agent_name'] = current_agent if current_agent.present?
    payload
  end

  def normalize_output(output)
    hash = coerce_to_hash(output)
    return fallback_payload(output) unless hash.is_a?(Hash)

    hash = unwrap_nested_response(hash)

    {
      'response' => (hash['response'] || hash[:response]).to_s,
      'reasoning' => (hash['reasoning'] || hash[:reasoning]).to_s
    }.with_indifferent_access
  end

  def unwrap_nested_response(hash)
    response_value = hash['response'] || hash[:response]
    return hash unless response_value.is_a?(String)

    inner = coerce_to_hash(response_value)
    return hash unless inner.is_a?(Hash) && (inner['response'] || inner[:response])

    inner
  end

  def coerce_to_hash(value)
    return value if value.is_a?(Hash)
    return nil unless value.is_a?(String)

    direct = parse_json(value)
    return direct if direct.is_a?(Hash)

    parse_first_json_object(value)
  end

  def parse_json(value)
    JSON.parse(value)
  rescue JSON::ParserError
    nil
  end

  def parse_first_json_object(value)
    depth = 0
    start_index = nil
    value.each_char.with_index do |ch, i|
      if ch == '{'
        start_index ||= i
        depth += 1
      elsif ch == '}' && start_index
        depth -= 1
        return parse_json(value[start_index..i]) if depth.zero?
      end
    end
    nil
  end

  def fallback_payload(output)
    {
      'response' => output.to_s,
      'reasoning' => 'Processed by JIVO agent'
    }.with_indifferent_access
  end

  def error_response(error_message)
    {
      'response' => Jivo::ConversationHandlerService::HANDOFF_SIGNAL,
      'reasoning' => "Error occurred: #{error_message}"
    }
  end
end
