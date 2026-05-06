class Jivo::Documents::FaqCoverageAuditService
  MAX_CONTENT_LENGTH = 30_000

  pattr_initialize [:assistant!, :content!, :faqs!]

  def perform
    return [] if content.blank?

    response = client.chat(parameters: request_parameters)
    parse_response(response)
  rescue OpenAI::Error => e
    Rails.logger.error "[JIVO] FAQ coverage audit failed: #{e.message}"
    []
  end

  private

  def request_parameters
    {
      model: assistant.model,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: system_prompt },
        { role: 'user', content: audit_content }
      ],
      temperature: 0.2
    }
  end

  def system_prompt
    <<~PROMPT
      You audit generated FAQs against source travel/product content.

      Find missing customer-facing information only. Focus on:
      - Products
      - Prices
      - Requirements
      - Inclusions and exclusions
      - Nationality or eligibility restrictions
      - Refund/payment policies
      - Mandatory notes and warnings

      Return JSON only:
      {
        "faqs": [
          { "question": "Question for missing information", "answer": "Answer using only source content" }
        ]
      }

      If nothing important is missing, return {"faqs":[]}.
      Do not duplicate existing FAQ questions.
      Do not invent information.
    PROMPT
  end

  def audit_content
    <<~CONTENT
      # Source content
      #{content.to_s[0, MAX_CONTENT_LENGTH]}

      # Existing generated FAQs
      #{faq_summary}
    CONTENT
  end

  def faq_summary
    faqs.map.with_index(1) do |faq, index|
      "#{index}. Q: #{faq['question']}\nA: #{faq['answer']}"
    end.join("\n\n")
  end

  def parse_response(response)
    content = response.dig('choices', 0, 'message', 'content')
    return [] if content.blank?

    JSON.parse(content.strip).fetch('faqs', [])
  rescue JSON::ParserError => e
    Rails.logger.error "[JIVO] FAQ coverage audit parse failed: #{e.message}"
    []
  end

  def client
    @client ||= OpenAI::Client.new(
      access_token: assistant.openai_api_key,
      log_errors: Rails.env.development?
    )
  end
end
