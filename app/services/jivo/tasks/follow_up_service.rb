class Jivo::Tasks::FollowUpService < Jivo::Tasks::BaseTaskService
  ALLOWED_EVENTS = %w[
    rewrite summarize reply_suggestion label_suggestion
    fix_spelling_grammar improve casual professional friendly confident straightforward
  ].freeze

  def initialize(assistant:, follow_up_context:, message:)
    super(assistant: assistant)
    @follow_up_context = follow_up_context || {}
    @message = message.to_s.strip[0, MAX_INPUT_LENGTH]
  end

  def perform
    return { success: false, error: 'Message is required' } if @message.blank?
    return { success: false, error: 'Invalid event_name' } unless ALLOWED_EVENTS.include?(event_name)

    super
  end

  protected

  def build_messages
    msgs = [{ role: 'system', content: system_prompt }]
    msgs.concat(history_messages)
    msgs.concat(previous_response_message)
    msgs << { role: 'user', content: @message }
    msgs
  end

  def build_result(response)
    content = response.dig('choices', 0, 'message', 'content').to_s.strip

    {
      success: true,
      message: content,
      follow_up_context: {
        event_name: event_name,
        original_context: @follow_up_context['original_context'],
        last_response: content,
        conversation_history: updated_history(content)
      }
    }
  end

  private

  def event_name
    @follow_up_context['event_name'].to_s
  end

  def history_messages
    Array(@follow_up_context['conversation_history']).map do |entry|
      {
        role: entry['role'].to_s.in?(%w[user assistant system]) ? entry['role'] : 'user',
        content: entry['content'].to_s
      }
    end
  end

  def previous_response_message
    return [] if last_response.blank?
    return [] if history_messages.any? { |entry| entry[:role] == 'assistant' && entry[:content] == last_response }

    [{ role: 'assistant', content: last_response }]
  end

  def last_response
    @follow_up_context['last_response'].to_s.strip
  end

  def updated_history(latest_response)
    history_messages + [
      { role: 'user', content: @message },
      { role: 'assistant', content: latest_response }
    ]
  end

  def system_prompt
    <<~PROMPT
      You are a writing assistant helping refine a previous output. The original task was: #{event_description}.

      The user is now giving you feedback to refine your previous response. Apply their feedback while staying true to the original task and context.

      Output ONLY the refined text — no preamble, no explanations.
    PROMPT
  end

  def event_description
    case event_name
    when 'fix_spelling_grammar' then 'fix spelling and grammar'
    when 'improve' then 'improve a written message'
    when 'casual', 'professional', 'friendly', 'confident', 'straightforward'
      "rewrite a message in a #{event_name} tone"
    when 'summarize' then 'summarize a conversation'
    when 'reply_suggestion' then 'suggest a reply for an agent'
    when 'label_suggestion' then 'suggest labels for a conversation'
    else 'process text'
    end
  end
end
