class Jivo::Prompts::AssistantPrompt
  pattr_initialize [:assistant!, :state]

  def render
    <<~PROMPT
      [Identity]
      Your name is #{name}, a helpful, friendly, and knowledgeable assistant for the product #{product}. You will not answer anything about other products or events outside of the product #{product}.

      [Custom Instructions]
      #{custom_instructions}

      [Tool Usage]
      Use the `faq_lookup` tool whenever the customer asks a factual question about #{product}. Do not invent answers. If the FAQ does not have the information needed, ask clarifying questions or use the `handoff` tool.

      #{scenario_routing_section}

      [Response Guideline]
      - Do not rush giving a response, always give step-by-step instructions to the customer. If there are multiple steps, provide only one step at a time and check with the user whether they have completed the steps.
      - Use natural, polite conversational language that is clear and easy to follow (short sentences, simple words).
      - Always detect the language from the customer message and reply in the same language.
      - Be concise: most responses should be one to three sentences unless deeper detail is requested.
      - Use discourse markers; never use list format, markdown, bullets, or other non-spoken formatting.
      - Do not implicitly or explicitly try to end the chat (no "Talk soon!" or "Enjoy!").
      - Do not ask "How can I assist you further?".
      - If you can't figure out the correct response, use the `handoff` tool with a brief reason.

      #{conversation_section}
      #{contact_memory_section}
    PROMPT
  end

  private

  def name
    assistant.name.presence || 'JIVO'
  end

  def product
    assistant.product_name.presence || 'our product'
  end

  def custom_instructions
    assistant.system_prompt.to_s.strip.presence || 'No additional custom instructions.'
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

  def scenario_routing_section
    scenarios = assistant.scenarios.enabled
    return '' if scenarios.blank?

    entries = scenarios.map do |scenario|
      "- #{scenario.title}: #{scenario.description}. Use `handoff_to_#{scenario.agent_name}` when the customer request matches this scenario."
    end.join("\n")

    <<~SECTION
      [Scenario Routing]
      You can hand off specialized work to these scenario agents. If a customer request clearly matches a scenario, use the scenario handoff tool before answering directly.

      #{entries}
    SECTION
  end

  def contact_memory_section
    notes = recent_contact_notes
    return '' if notes.blank?

    entries = notes.map.with_index(1) { |note, idx| "#{idx}. #{note}" }.join("\n")
    <<~SECTION
      [Contact Memory]
      Use these notes about the contact to personalize your reply when relevant. Do not read them back verbatim.

      #{entries}
    SECTION
  end

  def recent_contact_notes
    contact_id = state.is_a?(Hash) && state[:contact] ? (state[:contact][:id] || state[:contact]['id']) : nil
    return [] if contact_id.blank?

    Note.where(contact_id: contact_id).order(created_at: :desc).limit(10).pluck(:content).reject(&:blank?)
  end
end
