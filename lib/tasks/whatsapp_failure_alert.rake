namespace :whatsapp do
  desc 'Email an alert for new failed outgoing messages on Evolution WhatsApp inboxes'
  task failure_alert: :environment do
    recipient = ENV.fetch('WHATSAPP_ALERT_EMAIL', nil)
    if recipient.blank?
      Rails.logger.warn('[whatsapp:failure_alert] WHATSAPP_ALERT_EMAIL not set, skipping')
      next
    end

    watermark_key = 'whatsapp_failure_alert:last_message_id'
    last_id = Redis::Alfred.get(watermark_key).to_i

    evolution_inbox_ids = Inbox.where(channel_type: 'Channel::Api')
                               .select { |inbox| inbox.channel.additional_attributes&.dig('evolution_api') }
                               .map(&:id)

    current_max = Message.outgoing.where(inbox_id: evolution_inbox_ids).maximum(:id).to_i

    # First run: just record the watermark so we don't email the entire backlog.
    if last_id.zero?
      Redis::Alfred.set(watermark_key, current_max)
      Rails.logger.info("[whatsapp:failure_alert] initialised watermark at #{current_max}")
      next
    end

    failures = Message.outgoing
                      .where(status: :failed, inbox_id: evolution_inbox_ids)
                      .where('messages.id > ?', last_id)
                      .order(:id)
                      .to_a

    Redis::Alfred.set(watermark_key, current_max) if current_max.positive?
    next if failures.empty?

    inbox_names = Inbox.where(id: failures.map(&:inbox_id).uniq).pluck(:id, :name).to_h
    lines = failures.map do |message|
      error = message.content_attributes&.dig('external_error') || '(no error stored)'
      "#{message.created_at.utc.strftime('%Y-%m-%d %H:%M UTC')} | #{inbox_names[message.inbox_id]} | conv ##{message.conversation_id} | #{error}"
    end

    body = <<~BODY
      #{failures.size} new failed outgoing WhatsApp message(s) detected on Evolution inboxes.

      Note: "Timed out reading data from server" usually means the message WAS delivered but
      Evolution replied slower than WEBHOOK_TIMEOUT. Other errors are likely genuine failures.

      #{lines.join("\n")}
    BODY

    ActionMailer::Base.mail(
      from: ENV.fetch('MAILER_SENDER_EMAIL', 'alerts@chatwoot.com'),
      to: recipient,
      subject: "[Chatwoot] #{failures.size} WhatsApp send failure(s)",
      body: body
    ).deliver_now

    Rails.logger.info("[whatsapp:failure_alert] emailed #{failures.size} failure(s) to #{recipient}")
  end
end
