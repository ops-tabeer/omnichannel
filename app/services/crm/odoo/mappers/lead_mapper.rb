class Crm::Odoo::Mappers::LeadMapper
  include ::Rails.application.routes.url_helpers

  PLACEHOLDER_PHONE_PREFIX = 'N/A-conv'.freeze
  PLACEHOLDER_EMAIL_DOMAIN = 'chat.tabeertours.com'.freeze

  def self.map(conversation, partner_id, assignee_fields, partner_values = {})
    new(conversation, partner_values).map(partner_id, assignee_fields)
  end

  def initialize(conversation, partner_values = {})
    @conversation = conversation
    @inbox = conversation.inbox
    @partner_values = partner_values || {}
  end

  def map(partner_id, assignee_fields)
    {
      partner_id: partner_id,
      email_from: email_from,
      phone: phone,
      external_source_id: @conversation.display_id.to_s,
      communication_channel: communication_channel,
      source_platform: source_platform,
      lead_source: lead_source,
      chatwoot_conversation_url: conversation_url,
      lead_assignment_state: 'accepted'
    }.merge(assignee_fields)
  end

  private

  # Once a partner is matched/created it is the source of truth. The lead carries the
  # partner's own values (Odoo syncs email_from/phone onto the partner, so sending the
  # contact's values could overwrite a matched partner or collide with another partner's
  # uniquely-constrained phone). New partners are created from contact data, so their
  # read-back values already reflect the contact. Real value wins; otherwise reuse an
  # existing placeholder (no churn); otherwise mint a fresh one.
  def email_from
    real_partner_email ||
      @partner_values[:email].presence ||
      placeholder_email
  end

  def phone
    real_partner_phone ||
      @partner_values[:phone].presence ||
      placeholder_phone
  end

  def real_partner_email
    email = @partner_values[:email].presence
    email unless email.nil? || email.end_with?("@#{PLACEHOLDER_EMAIL_DOMAIN}")
  end

  def real_partner_phone
    phone = @partner_values[:phone].presence
    phone unless phone.nil? || placeholder_phone?(phone)
  end

  # crm.lead.phone is required and Odoo syncs it onto the partner, whose phone is
  # uniquely constrained. A shared constant collides, so phoneless contacts get a
  # per-conversation placeholder (legacy 'N/A' is still recognised as a placeholder).
  def placeholder_phone
    "#{PLACEHOLDER_PHONE_PREFIX}#{@conversation.display_id}"
  end

  def placeholder_phone?(phone)
    phone == 'N/A' || phone.start_with?(PLACEHOLDER_PHONE_PREFIX)
  end

  def placeholder_email
    "noreply+conv#{@conversation.display_id}@#{PLACEHOLDER_EMAIL_DOMAIN}"
  end

  def communication_channel
    if @inbox.facebook? || @inbox.instagram?
      'messenger'
    elsif @inbox.tiktok?
      'tiktok_messenger'
    elsif @inbox.whatsapp?
      'whatsapp'
    elsif @inbox.web_widget?
      'website_chat'
    elsif @inbox.email?
      'email'
    else
      'other'
    end
  end

  def source_platform
    return 'facebook' if @inbox.facebook?
    return 'instagram' if @inbox.instagram?
    return 'tiktok' if @inbox.tiktok?

    'custom_api'
  end

  # lead_source is marketing attribution, not channel; only some inbox types map
  # cleanly. WhatsApp and any unmatched channel fall through to 'other'.
  def lead_source
    return 'facebook_ad' if @inbox.facebook?
    return 'instagram' if @inbox.instagram?
    return 'tiktok' if @inbox.tiktok?
    return 'website' if @inbox.web_widget?
    return 'email' if @inbox.email?

    'other'
  end

  def conversation_url
    app_account_conversation_url(account_id: @conversation.account_id, id: @conversation.display_id)
  end
end
