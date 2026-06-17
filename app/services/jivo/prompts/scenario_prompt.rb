class Jivo::Prompts::ScenarioPrompt
  pattr_initialize [:scenario!, :state]

  def render
    <<~PROMPT
      [System Context]
      You are part of a multi-agent system. You have been handed off a conversation to handle a specific task. The handoff was seamless — the customer is not aware of any transfer. Continue the conversation naturally.

      [Your Role]
      You are a specialized agent called "#{scenario.title}". Your job:

      #{scenario.instruction}

      If the customer's request falls outside your role, hand the conversation back to the main agent using the `handoff_to_#{main_agent_handoff_key}` tool.

      [Product Context]
      Operate in the context of the product "#{product}". Do not answer questions about other products or events.

      [Response Guideline]
      - Respond in the customer's language.
      - Be concise — most replies should be one to three sentences.
      - Do not use markdown, lists, or bullets.
      - If you cannot complete the task, transfer back to the main agent rather than guessing.

      #{conversation_section}
      #{tools_section}
    PROMPT
  end

  private

  def main_agent_handoff_key
    scenario.jivo_assistant.agent_name.parameterize(separator: '_')
  end

  def product
    scenario.jivo_assistant.product_name.presence || 'our product'
  end

  def conversation_section
    convo = state.is_a?(Hash) ? state[:conversation] : nil
    return '' if convo.blank?

    <<~SECTION
      [Conversation Context]
      Conversation ID: #{convo[:display_id] || convo['display_id']}
      Status: #{convo[:status] || convo['status']}
      Priority: #{convo[:priority] || convo['priority'] || 'none'}
    SECTION
  end

  def tools_section
    tool_ids = scenario.tools.to_a
    return '' if tool_ids.blank?

    entries = tool_ids.map { |id| "- #{id}" }.join("\n")
    <<~SECTION
      [Available Tools]
      You have access to these tools:
      #{entries}
    SECTION
  end
end
