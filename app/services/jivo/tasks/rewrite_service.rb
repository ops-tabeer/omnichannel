class Jivo::Tasks::RewriteService < Jivo::Tasks::BaseTaskService
  ALLOWED_OPERATIONS = %w[
    fix_spelling_grammar improve casual professional friendly confident straightforward
  ].freeze

  TONE_OPERATIONS = %w[casual professional friendly confident straightforward].freeze

  def initialize(assistant:, content:, operation:, conversation: nil)
    super(assistant: assistant)
    @content = content.to_s.strip[0, MAX_INPUT_LENGTH]
    @operation = operation.to_s
    @conversation = conversation
  end

  def perform
    return { success: false, error: 'Invalid operation' } unless ALLOWED_OPERATIONS.include?(@operation)
    return { success: false, error: 'Content is required' } if @content.blank?

    super
  end

  protected

  def temperature
    TONE_OPERATIONS.include?(@operation) ? 0.1 : 0.4
  end

  def build_messages
    [
      { role: 'system', content: system_prompt },
      { role: 'user', content: @content }
    ]
  end

  def build_result(response)
    super.merge(operation: @operation)
  end

  private

  def system_prompt
    case @operation
    when 'fix_spelling_grammar'
      fix_spelling_grammar_prompt
    when 'improve'
      improve_prompt
    when *TONE_OPERATIONS
      tone_prompt
    end
  end

  def fix_spelling_grammar_prompt
    <<~PROMPT
      You are a writing assistant. Fix only the spelling and grammar of the user message.
      Preserve the meaning, tone, and style.
      Output ONLY the corrected text without any preamble or explanation.
    PROMPT
  end

  def improve_prompt
    context = conversation_context_block
    <<~PROMPT
      You are a writing assistant. Improve the clarity, structure, and flow of the user message while preserving its meaning and tone. Use the conversation context if relevant. Output ONLY the improved message without any preamble or explanation.

      #{context}
    PROMPT
  end

  def tone_prompt
    <<~PROMPT
      You are a writing assistant. Rewrite the user message in a #{@operation} tone. Preserve the meaning. Do not add information that is not in the original. Output ONLY the rewritten message without any preamble or explanation.
    PROMPT
  end

  def conversation_context_block
    return '' if @conversation.blank?

    history = @conversation.messages
                           .where(message_type: [:incoming, :outgoing], private: false)
                           .order(:created_at)
                           .last(20)
                           .map { |m| "#{m.message_type == 'incoming' ? 'Customer' : 'Agent'}: #{m.content}" }
                           .join("\n")

    return '' if history.blank?

    "Conversation context:\n#{history}"
  end
end
