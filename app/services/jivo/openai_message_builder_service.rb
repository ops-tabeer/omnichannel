class Jivo::OpenaiMessageBuilderService
  pattr_initialize [:message!, [:assistant]]

  def self.extract_text_and_attachments(content)
    return [content, []] unless content.is_a?(Array)

    text_parts = content.select { |part| part[:type] == 'text' }.pluck(:text)
    image_urls = content.select { |part| part[:type] == 'image_url' }.filter_map { |part| part.dig(:image_url, :url) }
    [text_parts.join(' ').presence, image_urls]
  end

  def generate_content
    parts = []
    parts << text_part(@message.content) if @message.content.present?
    parts.concat(attachment_parts) if @message.attachments.any?

    return 'Message without content' if parts.blank?
    return parts.first[:text] if parts.one? && parts.first[:type] == 'text'

    parts
  end

  private

  def text_part(text)
    { type: 'text', text: text.to_s }
  end

  def image_part(url)
    { type: 'image_url', image_url: { url: url } }
  end

  def attachment_parts
    parts = []
    parts.concat(image_attachment_parts)

    transcription = audio_transcripts_text
    parts << text_part(transcription) if transcription.present?

    parts << text_part('User has shared an attachment') if @message.attachments.where.not(file_type: %i[image audio]).exists?

    parts
  end

  def image_attachment_parts
    @message.attachments.where(file_type: :image).filter_map do |att|
      url = attachment_url(att)
      image_part(url) if url.present?
    end
  end

  def audio_transcripts_text
    audio_atts = @message.attachments.where(file_type: :audio)
    return '' if audio_atts.blank?

    transcripts = audio_atts.filter_map { |att| transcript_for(att) }
    return '' if transcripts.blank?

    "Customer audio message transcript: #{transcripts.join(' | ')}"
  end

  def transcript_for(attachment)
    cached = attachment.meta&.dig('transcribed_text').presence
    return cached if cached.present?
    return nil if @assistant.blank?

    Jivo::Messages::AudioTranscriptionService.new(
      attachment: attachment,
      assistant: @assistant
    ).perform.presence
  end

  def attachment_url(attachment)
    return attachment.download_url if attachment.respond_to?(:download_url) && attachment.download_url.present?
    return attachment.external_url if attachment.external_url.present?

    attachment.file.attached? ? attachment.file_url : nil
  end
end
