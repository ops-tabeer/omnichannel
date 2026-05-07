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
      prompt_from_file('fix_spelling_grammar')
    when 'improve'
      improve_prompt
    when *TONE_OPERATIONS
      tone_prompt
    end
  end

  def improve_prompt
    template = prompt_from_file('improve')
    render_liquid_template(template, {
                             'conversation_context' => conversation_context_text,
                             'draft_message' => @content
                           })
  end

  def tone_prompt
    template = prompt_from_file('tone_rewrite')
    render_liquid_template(template, 'tone' => @operation)
  end

  def conversation_context_text
    return '' if @conversation.blank?

    @conversation.to_llm_text(include_contact_details: true)
  rescue StandardError
    # Fallback to basic formatting if to_llm_text is not available
    fallback_conversation_context
  end

  def fallback_conversation_context
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
