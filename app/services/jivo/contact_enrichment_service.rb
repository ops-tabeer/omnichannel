class Jivo::ContactEnrichmentService
  SUPPORTED_ATTRIBUTES = %w[name email phone_number].freeze
  RECENT_MESSAGE_LIMIT = 25
  EMAIL_REGEX = /[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}/i
  PHONE_REGEX = /\+?\d[\d\s().-]{6,}\d/
  NAME_SIGNAL_REGEX = /\b(my name is|i am|i'm|this is)\b/i
  ENRICHED_MESSAGE_ID_KEY = 'jivo_contact_enriched_message_id'.freeze
  RAW_PHONE_ATTRIBUTE = 'raw_phone_number'.freeze

  pattr_initialize [:conversation!, :assistant!]

  def perform
    return unless should_attempt_enrichment?

    apply_attributes(deterministic_attributes)
    return mark_message_checked unless should_call_llm?

    attributes = Jivo::Llm::ContactAttributesService.new(assistant: assistant, conversation: conversation).generate
    mark_message_checked
    return if attributes.blank?

    apply_attributes(attributes)
  rescue StandardError => e
    Rails.logger.warn "[JIVO] ContactEnrichmentService skipped for conversation #{conversation.id}: #{e.message}"
    Rails.logger.warn e.backtrace.first(5).join("\n")
  end

  private

  delegate :account, :contact, to: :conversation

  def should_attempt_enrichment?
    enrichment_message.present? &&
      missing_supported_attribute? &&
      enrichment_signal_present?
  end

  def enrichment_message
    @enrichment_message ||= recent_incoming_messages.find { |message| enrichment_signal_present?(message.content.to_s) }
  end

  def missing_supported_attribute?
    contact.email.blank? || contact.phone_number.blank? || name_missing?
  end

  def message_not_checked?
    checked_message_id != enrichment_message.id
  end

  def enrichment_signal_present?(content = message_content)
    content.match?(EMAIL_REGEX) || content.match?(PHONE_REGEX) || content.match?(NAME_SIGNAL_REGEX)
  end

  def message_content
    @message_content ||= enrichment_message.content.to_s
  end

  def recent_incoming_messages
    @recent_incoming_messages ||= begin
      scope = conversation.messages.incoming.where(private: false)
      scope = scope.where('id > ?', checked_message_id) if checked_message_id.positive?
      scope.order(id: :desc).limit(RECENT_MESSAGE_LIMIT).to_a
    end
  end

  def checked_message_id
    conversation.custom_attributes[ENRICHED_MESSAGE_ID_KEY].to_i
  end

  def deterministic_attributes
    [
      { 'attribute' => 'email', 'value' => scan_recent_messages(EMAIL_REGEX) },
      { 'attribute' => 'phone_number', 'value' => scan_recent_messages(PHONE_REGEX) }
    ]
  end

  def scan_recent_messages(regex)
    recent_incoming_messages.each do |message|
      match = message.content.to_s[regex]
      return match if match.present?
    end
    ''
  end

  def should_call_llm?
    message_not_checked? && missing_supported_attribute? && message_content.match?(NAME_SIGNAL_REGEX)
  end

  def mark_message_checked
    conversation.update!(
      custom_attributes: conversation.custom_attributes.to_h.merge(ENRICHED_MESSAGE_ID_KEY => enrichment_message.id)
    )
  end

  def apply_attributes(attributes)
    updates = {}
    attributes.each do |item|
      attribute = item['attribute'].to_s
      value = item['value'].to_s.strip
      next unless SUPPORTED_ATTRIBUTES.include?(attribute)
      next if value.blank?

      if attribute == 'phone_number'
        apply_phone(value, updates)
      else
        applied_value = send("extract_#{attribute}", value)
        updates[attribute] = applied_value if applied_value.present?
      end
    end

    return if updates.blank?

    contact.update!(updates)
    Rails.logger.info "[JIVO] Contact enrichment updated contact #{contact.id}: #{updates.keys.join(', ')}"
  end

  def extract_name(value)
    return nil unless name_missing?

    value
  end

  def extract_email(value)
    email = value.downcase
    return nil if contact.email.present?
    return nil unless email.match?(Devise.email_regexp)
    return nil if email_taken?(email)

    email
  end

  def email_taken?(email)
    account.contacts.where.not(id: contact.id).where('LOWER(email) = ?', email).pick(:id).present?
  end

  # Stores a valid E.164 number on the phone_number column; otherwise keeps the raw
  # digits in additional_attributes (the Contact model rejects non-E.164 phone_number)
  # so a local-format number sent in chat is never dropped before reaching Odoo.
  def apply_phone(value, updates)
    return if contact.phone_number.present?

    phone_number = normalized_phone_number(value)
    if phone_number.present?
      return if account.contacts.where.not(id: contact.id).exists?(phone_number: phone_number)

      updates['phone_number'] = phone_number
    elsif contact.additional_attributes[RAW_PHONE_ATTRIBUTE].blank?
      updates['additional_attributes'] = contact.additional_attributes.merge(RAW_PHONE_ATTRIBUTE => value.gsub(/[^\d+]/, ''))
    end
  end

  def normalized_phone_number(value)
    compact_value = value.to_s.gsub(/[^\d+]/, '')
    return nil if compact_value.blank?

    parsed = TelephoneNumber.parse(compact_value)
    return parsed.e164_number if parsed.valid?

    parsed = TelephoneNumber.parse("+#{compact_value}") unless compact_value.start_with?('+')
    return parsed.e164_number if parsed&.valid?

    nil
  end

  def name_missing?
    contact.name.blank? || contact.name == contact.phone_number || contact.name == contact.email || contact.name.to_s.end_with?('@s.whatsapp.net')
  end
end
