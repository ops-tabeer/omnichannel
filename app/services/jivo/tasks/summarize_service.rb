class Jivo::Tasks::SummarizeService < Jivo::Tasks::BaseTaskService
  def initialize(assistant:, conversation:)
    super(assistant: assistant)
    @conversation = conversation
  end

  protected

  def build_messages
    [
      { role: 'system', content: prompt_from_file('summary') },
      { role: 'user', content: conversation_text }
    ]
  end

  private

  def conversation_text
    @conversation.to_llm_text(include_contact_details: false)
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

    return 'No conversation messages.' if text.blank?

    text
  end
end
