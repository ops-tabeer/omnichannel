class Jivo::Tasks::SummarizeService < Jivo::Tasks::BaseTaskService
  def initialize(assistant:, conversation:)
    super(assistant: assistant)
    @conversation = conversation
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
    <<~PROMPT
      You are a customer support assistant. Summarize the following conversation between a customer and a support agent.

      Output a concise summary in 3-5 sentences covering:
      - What the customer is asking about or the issue raised
      - Key actions taken or information shared
      - Current state or next steps if any

      Output only the summary text — no preamble, no markdown, no headings.
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

    return 'No conversation messages.' if text.blank?

    text
  end
end
