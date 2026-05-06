require 'net/http'

class Jivo::Messages::AudioTranscriptionService
  WHISPER_MODEL = 'whisper-1'.freeze
  FALLBACK_MODEL = 'gpt-4o-mini-transcribe'.freeze
  OPENAI_TRANSCRIPTION_URL = 'https://api.openai.com/v1/audio/transcriptions'.freeze
  REQUEST_TIMEOUT = 90

  pattr_initialize [:attachment!, :assistant!]

  def perform
    cached = attachment.meta&.dig('transcribed_text')
    return cached if cached.present?
    return '' unless attachment.file.attached?
    raise 'OpenAI API key not configured for assistant' if assistant.openai_api_key.blank?

    transcript = transcribe
    save_transcript(transcript) if transcript.present?
    transcript
  rescue StandardError => e
    Rails.logger.error "[JIVO] AudioTranscriptionService error for attachment #{attachment.id}: #{e.message}"
    ChatwootExceptionTracker.new(e, account: assistant.account).capture_exception
    ''
  end

  private

  def transcribe
    temp_path = write_audio_to_temp_file
    post_to_whisper(temp_path, model: WHISPER_MODEL)
  rescue StandardError => e
    Rails.logger.warn "[JIVO] Whisper primary model failed (#{WHISPER_MODEL}): #{e.message}; retrying with #{FALLBACK_MODEL}"
    post_to_whisper(temp_path, model: FALLBACK_MODEL)
  ensure
    FileUtils.rm_f(temp_path) if temp_path
  end

  def write_audio_to_temp_file
    blob = attachment.file.blob
    temp_dir = Rails.root.join('tmp/uploads/jivo-audio')
    FileUtils.mkdir_p(temp_dir)
    file_name = "#{blob.key}-#{blob.filename}"
    file_name = "#{file_name}.#{extension_from_content_type(blob.content_type)}" if blob.filename.extension_without_delimiter.blank?
    path = File.join(temp_dir, file_name)

    File.open(path, 'wb') do |f|
      blob.open { |blob_file| IO.copy_stream(blob_file, f) }
    end
    path
  end

  def post_to_whisper(file_path, model: WHISPER_MODEL)
    uri = URI.parse(OPENAI_TRANSCRIPTION_URL)
    boundary = "JivoAudio-#{SecureRandom.hex(8)}"

    response = whisper_http_client(uri).request(whisper_request(uri, file_path, boundary, model))
    raise "Whisper API error #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)['text'].to_s.strip
  end

  def whisper_http_client(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = REQUEST_TIMEOUT
    http
  end

  def whisper_request(uri, file_path, boundary, model)
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
    request['Authorization'] = "Bearer #{assistant.openai_api_key}"
    request.body = build_multipart_body(file_path, boundary, model)
    request
  end

  def build_multipart_body(file_path, boundary, model)
    eol = "\r\n"
    body = +''
    body << "--#{boundary}#{eol}"
    body << %(Content-Disposition: form-data; name="model"#{eol}#{eol})
    body << "#{model}#{eol}"
    if account_language_hint.present?
      body << "--#{boundary}#{eol}"
      body << %(Content-Disposition: form-data; name="language"#{eol}#{eol})
      body << "#{account_language_hint}#{eol}"
    end
    body << "--#{boundary}#{eol}"
    body << %(Content-Disposition: form-data; name="file"; filename="#{File.basename(file_path)}"#{eol})
    body << "Content-Type: application/octet-stream#{eol}#{eol}"
    body << File.binread(file_path)
    body << "#{eol}--#{boundary}--#{eol}"
    body
  end

  def account_language_hint
    @account_language_hint ||= assistant.account.locale.to_s.split('_').first.presence
  end

  def save_transcript(text)
    meta = (attachment.meta || {}).merge('transcribed_text' => text)
    attachment.update_columns(meta: meta) # rubocop:disable Rails/SkipsModelValidations
  end

  def extension_from_content_type(content_type)
    subtype = content_type.to_s.downcase.split(';').first.to_s.split('/').last.to_s
    return 'mp3' if subtype.blank?

    {
      'x-m4a' => 'm4a', 'x-wav' => 'wav', 'x-mp3' => 'mp3',
      'mpeg' => 'mp3', 'ogg' => 'ogg', 'webm' => 'webm', 'mp4' => 'mp4'
    }.fetch(subtype, subtype)
  end
end
