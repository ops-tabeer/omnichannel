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
      { role: 'user', content: conversation_text }
    ]
  end

  private

  def system_prompt
    agent_name = @agent&.name.presence || 'a support agent'
    channel_type = @conversation.inbox.channel_type.to_s.split('::').last

    <<~PROMPT
      You are #{agent_name}, drafting a reply for a customer support agent on #{channel_type}.

      Read the conversation and draft the next reply the agent should send to the customer.

      Guidelines:
      - Match the language the customer is using
      - Keep it natural and conversational, 1-3 sentences
      - Be professional but warm
      - Address the customer's most recent question or concern
      - Don't add greetings if the conversation is already in progress
      - Don't sign off with "Best regards" or signatures

      Output ONLY the suggested reply text — no preamble, no quotes, no labels.
    PROMPT
  end

  def conversation_text
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
