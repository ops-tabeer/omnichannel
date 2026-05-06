module Jivo::Prompts::Concerns::GuidelinesFormatter
  private

  def custom_response_guidelines_section
    guidelines = Array(prompt_assistant.response_guidelines).reject(&:blank?)
    return '' if guidelines.blank?

    "\n[Custom Response Guidelines]\n#{guidelines.map { |g| "- #{g}" }.join("\n")}"
  end

  def guardrails_section
    guardrails = Array(prompt_assistant.guardrails).reject(&:blank?)
    return '' if guardrails.blank?

    <<~SECTION

      [Guardrails]
      Always respect these boundaries:
      #{guardrails.map { |g| "- #{g}" }.join("\n")}
    SECTION
  end
end
