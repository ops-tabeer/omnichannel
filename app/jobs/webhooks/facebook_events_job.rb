class Webhooks::FacebookEventsJob < MutexApplicationJob
  queue_as :default
  retry_on LockAcquisitionError, wait: 1.second, attempts: 8

  def perform(message)
    response = ::Integrations::Facebook::MessageParser.new(message)

    # TEMP DEBUG: capture the raw attachment payload of shared posts to determine their type. Remove after diagnosis.
    Rails.logger.info("[FB_ATTACHMENT_DEBUG] attachments=#{response.attachments.inspect}") if response.attachments.present?

    key = format(::Redis::Alfred::FACEBOOK_MESSAGE_MUTEX, sender_id: response.sender_id, recipient_id: response.recipient_id)
    with_lock(key) do
      process_message(response)
    end
  end

  def process_message(response)
    ::Integrations::Facebook::MessageCreator.new(response).perform
  end
end
