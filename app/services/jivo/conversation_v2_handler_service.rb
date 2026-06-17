class Jivo::ConversationV2HandlerService
  HANDOFF_SIGNAL = Jivo::ConversationHandlerService::HANDOFF_SIGNAL
  MAX_MESSAGE_LENGTH = 10_000

  pattr_initialize [:conversation!, :assistant!]

  def perform
    enrich_contact
    history = build_message_history
    result = Jivo::Assistant::AgentRunnerService.new(
      assistant: assistant,
      conversation: conversation
    ).generate_response(message_history: history)

    handle_result(result)
  rescue StandardError => e
    Rails.logger.error "[JIVO V2] handler error for conversation #{conversation.id}: #{e.message}"
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    perform_handoff(assistant.handoff_message_text)
  end

  private

  delegate :account, :inbox, to: :conversation

  def enrich_contact
    Jivo::ContactEnrichmentService.new(conversation: conversation, assistant: assistant).perform
  end

  def build_message_history
    conversation.messages
                .where(message_type: [:incoming, :outgoing])
                .where(private: false)
                .order(:created_at)
                .map { |msg| message_payload(msg) }
                .reject { |m| blank_payload?(m) }
  end

  def message_payload(msg)
    content = Jivo::OpenaiMessageBuilderService.new(message: msg, assistant: assistant).generate_content
    content = content.strip[0, MAX_MESSAGE_LENGTH] if content.is_a?(String)

    {
      role: msg.message_type == 'incoming' ? :user : :assistant,
      content: content
    }
  end

  def blank_payload?(payload)
    content = payload[:content]
    return true if content.blank?
    return true if content.is_a?(String) && content.strip.empty?

    false
  end

  def handle_result(result)
    reply = result['response'].to_s.strip

    if reply == HANDOFF_SIGNAL
      perform_handoff(assistant.handoff_message_text)
    elsif reply.present?
      create_outgoing_message(reply, scenario_label_for(result['agent_name']), citations_for(result))
    else
      raise 'JIVO V2 agent returned blank response'
    end
  end

  def scenario_label_for(agent_name)
    return nil if agent_name.blank?
    return nil if agent_name == assistant.agent_name

    assistant.scenarios.enabled.find { |s| s.agent_name == agent_name }&.title
  end

  def citations_for(result)
    return nil unless assistant.feature_citation_enabled?

    citations = Array(result['citations']).map { |c| c.respond_to?(:with_indifferent_access) ? c.with_indifferent_access : c.stringify_keys }
    return nil if citations.empty?

    citations.map do |c|
      { document_id: c['document_id'], external_link: c['external_link'], document_name: c['document_name'], question: c['question'] }
    end
  end

  def create_outgoing_message(content, scenario_label = nil, citations = nil)
    attrs = {
      message_type: :outgoing,
      account_id: account.id,
      inbox_id: inbox.id,
      sender: assistant,
      content: content,
      private: false
    }
    content_attrs = {}
    content_attrs[:jivo_scenario] = scenario_label if scenario_label.present?
    content_attrs[:citations] = citations if citations.present?
    attrs[:content_attributes] = content_attrs if content_attrs.any?
    conversation.messages.create!(attrs)
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
      conversation.update!(custom_attributes: conversation.custom_attributes.merge('ai_handoff' => true))
      conversation.bot_handoff!
    end
  end
end
