class Jivo::Tasks::ReplySuggestionService < Jivo::Tasks::BaseTaskService
  def initialize(assistant:, conversation:, agent: nil)
    super(assistant: assistant)
    @conversation = conversation
    @agent = agent
  end

  protected

  def build_messages
    [
      { role: 'system', content: system_prompt },
      { role: 'user', content: formatted_conversation }
    ]
  end

  private

  def system_prompt
    template = prompt_from_file('reply')
    render_liquid_template(template, prompt_variables)
  end

  def prompt_variables
    {
      'channel_type' => @conversation.inbox.channel_type.to_s,
      'agent_name' => @agent&.name.presence || 'a support agent',
      'agent_signature' => @agent&.message_signature.presence
    }
  end

  def formatted_conversation
    LlmFormatter::ConversationLlmFormatter.new(@conversation).format(token_limit: MAX_INPUT_LENGTH)
  rescue StandardError
    fallback_conversation_text
  end

  def fallback_conversation_text
    messages = @conversation.messages
                            .where(message_type: [:incoming, :outgoing], private: false)
                            .order(:created_at)

    text = messages.map do |m|
      role = m.message_type == 'incoming' ? 'Customer' : 'Agent'
      "#{role}: #{m.content.to_s.strip}"
    end.join("\n").strip[0, MAX_INPUT_LENGTH]

    return 'No prior conversation. Start with a greeting.' if text.blank?

    text
  end
end
