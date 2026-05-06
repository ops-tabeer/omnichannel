class Jivo::Llm::FaqGeneratorService
  OPENAI_API_URL = 'https://api.openai.com/v1/chat/completions'.freeze
  REQUEST_TIMEOUT = 90
  MAX_CONTENT_LENGTH = 30_000

  pattr_initialize [:assistant!, :content!]

  def generate
    return [] if content.blank?
    raise 'OpenAI API key not configured' if assistant.openai_api_key.blank?

    response = call_openai
    parse_faqs(response)
  rescue StandardError => e
    Rails.logger.error "[JIVO] FAQ generation failed: #{e.message}"
    ChatwootExceptionTracker.new(e).capture_exception
    []
  end

  private

  def call_openai
    uri = URI.parse(OPENAI_API_URL)
    response = openai_http_client(uri).request(openai_request(uri))
    raise "OpenAI error #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def openai_http_client(uri)
    Net::HTTP.new(uri.host, uri.port).tap do |http|
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = REQUEST_TIMEOUT
    end
  end

  def openai_request(uri)
    Net::HTTP::Post.new(uri).tap do |request|
      request['Content-Type'] = 'application/json'
      request['Authorization'] = "Bearer #{assistant.openai_api_key}"
      request.body = request_body.to_json
    end
  end

  def request_body
    {
      model: assistant.model,
      messages: [
        { role: 'system', content: system_prompt },
        { role: 'user', content: content.to_s[0, MAX_CONTENT_LENGTH] }
      ],
      response_format: { type: 'json_object' },
      temperature: 0.3
    }
  end

  def parse_faqs(response)
    raw = response.dig('choices', 0, 'message', 'content')
    return [] if raw.blank?

    parsed = JSON.parse(raw)
    Array(parsed['faqs']).select { |f| f['question'].present? && f['answer'].present? }
  rescue JSON::ParserError
    []
  end

  def system_prompt
    <<~PROMPT
      You are a content writer specializing in creating FAQs from source content.

      ## Core Requirements
      - **Completeness**: Extract ALL information from the source. Every detail, procedure, and example must be captured.
      - **Accuracy**: Base answers strictly on the provided text. Do not add external knowledge.
      - **Structured blocks**: Do not only extract explicit Q/A pairs. Convert standalone Product, Cost, Details, Requirements, Inclusions, Notes, restrictions, policies, and warnings into FAQs.
      - **Preserve business-critical details**: Keep every price, nationality restriction, eligibility rule, refund rule, requirement, inclusion, exclusion, and mandatory note.
      - **Format**: Return valid JSON in this exact structure:

      ```json
      {
        "faqs": [
          { "question": "Clear, specific question based on content", "answer": "Complete answer with all relevant details" }
        ]
      }
      ```

      ## Guidelines
      - Generate questions that naturally arise from the content (What is...? How do I...? When should...?).
      - Answers should be self-contained and include all relevant details.
      - If a Product/Cost block has no question, create a natural customer question for it.
      - If a note changes who a price applies to, include that note in the answer.
      - If no useful content found, return: `{"faqs": []}`
      - Only return valid JSON. Do not include any other text.
    PROMPT
  end
end
