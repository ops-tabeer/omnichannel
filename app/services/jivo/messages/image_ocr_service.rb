require 'net/http'

class Jivo::Messages::ImageOcrService
  OPENAI_API_URL = 'https://api.openai.com/v1/chat/completions'.freeze
  OCR_MODEL = 'gpt-4o-mini'.freeze
  REQUEST_TIMEOUT = 60

  pattr_initialize [:attachment!, :assistant!]

  def perform
    cached = attachment.meta&.dig('jivo_ocr_text')
    return cached if cached.present?
    return '' if assistant.openai_api_key.blank?

    url = image_url
    return '' if url.blank?

    text = call_openai(url).to_s.strip
    save_ocr_text(text) if text.present?
    text
  rescue StandardError => e
    Rails.logger.warn "[JIVO] ImageOcrService failed for attachment #{attachment.id}: #{e.message}"
    ''
  end

  private

  def image_url
    return attachment.download_url if attachment.respond_to?(:download_url) && attachment.download_url.present?
    return attachment.external_url if attachment.external_url.present?

    attachment.file.attached? ? attachment.file_url : nil
  end

  def call_openai(url)
    uri = URI.parse(OPENAI_API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = REQUEST_TIMEOUT

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{assistant.openai_api_key}"
    request.body = body_for(url).to_json

    response = http.request(request)
    raise "OCR API error #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).dig('choices', 0, 'message', 'content')
  end

  def body_for(url)
    {
      model: OCR_MODEL,
      temperature: 0,
      messages: [
        { role: 'system', content: system_prompt },
        {
          role: 'user',
          content: [
            { type: 'text', text: 'Extract every visible piece of text and key visual information from this image. Return plain text only.' },
            { type: 'image_url', image_url: { url: url } }
          ]
        }
      ]
    }
  end

  def system_prompt
    'You read text content out of customer-shared images for a support assistant. Reply with the extracted text only, no commentary.'
  end

  def save_ocr_text(text)
    meta = (attachment.meta || {}).merge('jivo_ocr_text' => text)
    attachment.update_columns(meta: meta) # rubocop:disable Rails/SkipsModelValidations
  end
end
