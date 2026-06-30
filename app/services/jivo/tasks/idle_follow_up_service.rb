class Jivo::Tasks::IdleFollowUpService < Jivo::Tasks::BaseTaskService
  ACTIONS = %w[follow_up handoff wait].freeze
  MAX_MESSAGE_LENGTH = 10_000

  # Returns { success: true, action: 'follow_up'|'handoff'|'wait', message: } based on the
  # assistant's idle_prompt and the conversation so far. Any failure (API error, blank
  # prompt, invalid output) degrades to a safe 'wait' so the job never acts on garbage.
  protected

  def use_json_response?
    true
  end

  def build_messages
    [{ role: 'system', content: system_prompt }] + conversation_history
  end

  def build_result(response)
    content = response.dig('choices', 0, 'message', 'content').to_s
    parsed = JSON.parse(content)
    action = parsed['action'].to_s
    return wait_result unless ACTIONS.include?(action)

    { success: true, action: action, message: parsed['message'].to_s.strip }
  rescue JSON::ParserError
    wait_result
  end

  private

  def conversation
    opts[:conversation]
  end

  def wait_result
    { success: true, action: 'wait', message: '' }
  end

  def conversation_history
    conversation.messages
                .where(message_type: [:incoming, :outgoing])
                .where(private: false)
                .order(:created_at)
                .map { |msg| message_payload(msg) }
                .reject { |payload| payload[:content].blank? }
  end

  def message_payload(msg)
    { role: msg.message_type == 'incoming' ? 'user' : 'assistant', content: build_content(msg) }
  end

  def build_content(msg)
    content = Jivo::OpenaiMessageBuilderService.new(message: msg, assistant: assistant).generate_content
    content.is_a?(String) ? content.strip[0, MAX_MESSAGE_LENGTH] : content
  end

  def system_prompt
    <<~PROMPT
      You decide the next step for an idle customer conversation — the customer has gone quiet.
      Follow the instruction below and the conversation so far to pick exactly one action.

      [Instruction]
      #{assistant.idle_prompt}

      [Actions]
      - "follow_up": send a short message to the customer (put it in "message").
      - "handoff": hand the conversation to a human agent now (no message needed).
      - "wait": do nothing right now.

      [Rules]
      - Write "message" in the same language as the customer's most recent messages.
      - Keep it short and natural (one or two sentences). No lists or markdown.
      - Respond ONLY as valid JSON: {"action": "follow_up|handoff|wait", "message": ""}
    PROMPT
  end
end
