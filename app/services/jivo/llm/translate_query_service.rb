require 'net/http'

class Jivo::Llm::TranslateQueryService
  OPENAI_API_URL = 'https://api.openai.com/v1/chat/completions'.freeze
  MODEL = 'gpt-4.1-nano'.freeze
  REQUEST_TIMEOUT = 30

  pattr_initialize [:assistant!]

  def translate(query, target_language:)
    return query if query.blank?
    return query if query_in_target_language?(query)
    return query if assistant.openai_api_key.blank?

    response = call_openai(query, target_language)
    response.dig('choices', 0, 'message', 'content').to_s.strip.presence || query
  rescue StandardError => e
    Rails.logger.warn "[JIVO] TranslateQueryService failed: #{e.message}, falling back to original query"
    query
  end

  private

  def query_in_target_language?(query)
    detector = CLD3::NNetLanguageIdentifier.new(0, 1000)
    result = detector.find_language(query)

    result.reliable? && result.language == account_language_code
  rescue StandardError
    false
  end

  def account_language_code
    assistant.account.locale&.split('_')&.first
  end

  def call_openai(query, target_language)
    uri = URI.parse(OPENAI_API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = REQUEST_TIMEOUT

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{assistant.openai_api_key}"
    request.body = {
      model: MODEL,
      messages: [
        { role: 'system', content: system_prompt(target_language) },
        { role: 'user', content: query }
      ],
      temperature: 0
    }.to_json

    response = http.request(request)
    raise "OpenAI API error #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def system_prompt(target_language)
    <<~PROMPT
      You are a helpful assistant that translates customer support queries.
      Translate the query to #{target_language}.
      Return only the translated query, with no explanation or extra text.
    PROMPT
  end
end
