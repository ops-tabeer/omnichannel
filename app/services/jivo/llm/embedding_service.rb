class Jivo::Llm::EmbeddingService
  OPENAI_EMBEDDING_URL = 'https://api.openai.com/v1/embeddings'.freeze
  EMBEDDING_MODEL = 'text-embedding-3-small'.freeze
  REQUEST_TIMEOUT = 30

  pattr_initialize [:assistant!]

  def get_embedding(text)
    return nil if text.blank?
    raise 'OpenAI API key not configured for assistant' if assistant.openai_api_key.blank?

    response = call_openai(text)
    response.dig('data', 0, 'embedding')
  end

  private

  def call_openai(text)
    uri = URI.parse(OPENAI_EMBEDDING_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = REQUEST_TIMEOUT

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{assistant.openai_api_key}"
    request.body = {
      model: EMBEDDING_MODEL,
      input: text.to_s.strip[0, 8000]
    }.to_json

    response = http.request(request)
    raise "OpenAI Embedding error #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end
end
