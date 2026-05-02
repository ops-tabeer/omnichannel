class Jivo::Messages::AudioTranscriptionJob < ApplicationJob
  queue_as :default

  retry_on Net::ReadTimeout, attempts: 2, wait: 3.seconds

  def perform(attachment, assistant)
    return if attachment.blank? || assistant.blank?

    Jivo::Messages::AudioTranscriptionService.new(
      attachment: attachment,
      assistant: assistant
    ).perform
  end
end
