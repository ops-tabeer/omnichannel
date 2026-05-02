class Jivo::Tasks::LabelSuggestionService < Jivo::Tasks::BaseTaskService
  def initialize(assistant:, conversation:)
    super(assistant: assistant)
    @conversation = conversation
  end

  def perform
    return { success: true, message: '', labels: [] } if available_labels.empty?

    super
  end

  protected

  def use_json_response?
    true
  end

  def build_messages
    [
      { role: 'system', content: system_prompt },
      { role: 'user', content: conversation_text }
    ]
  end

  def build_result(response)
    raw = response.dig('choices', 0, 'message', 'content').to_s
    parsed = JSON.parse(raw)
    suggested = Array(parsed['labels']).map(&:to_s).map(&:strip).reject(&:blank?)

    valid_labels = suggested & available_labels.map(&:title)
    { success: true, message: valid_labels.join(', '), labels: valid_labels }
  rescue JSON::ParserError => e
    { success: false, error: "Failed to parse JSON: #{e.message}" }
  end

  private

  def system_prompt
    label_list = available_labels.map(&:title).join(', ')

    <<~PROMPT
      You are a conversation classifier. Read the conversation and pick relevant labels from this list ONLY:
      #{label_list}

      Pick 1-3 most relevant labels. Do not invent new labels. If none apply, return an empty array.

      Output a JSON object in this exact format:
      {"labels": ["label1", "label2"]}

      Output ONLY the JSON object — no preamble.
    PROMPT
  end

  def conversation_text
    messages = @conversation.messages
                            .where(message_type: [:incoming, :outgoing], private: false)
                            .order(:created_at)

    messages.map do |m|
      role = m.message_type == 'incoming' ? 'Customer' : 'Agent'
      "#{role}: #{m.content.to_s.strip}"
    end.join("\n").strip[0, MAX_INPUT_LENGTH]
  end

  def available_labels
    @available_labels ||= @conversation.account.labels
  end
end
