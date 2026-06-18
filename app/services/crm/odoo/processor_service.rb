class Crm::Odoo::ProcessorService < Crm::BaseProcessorService
  def self.crm_name
    'odoo'
  end

  def initialize(hook)
    super(hook)
    @client = Crm::Odoo::Api::Client.new(
      url: hook.settings['url'],
      db: hook.settings['db'],
      login: hook.settings['login'],
      api_key: hook.access_token
    )
  end

  # Creates the Odoo lead when an agent takes a handed-off conversation.
  def handle_taken(conversation)
    return unless inbox_enabled?(conversation)
    return if lead_id(conversation).present?

    partner_id = find_or_create_partner(conversation.contact)
    partner_values = partner_contact_values(partner_id)
    lead_data = Crm::Odoo::Mappers::LeadMapper.map(conversation, partner_id, salesperson_fields(conversation.assignee), partner_values)
    new_lead_id = @client.execute_kw('crm.lead', 'create', [lead_data])
    store_conversation_metadata(conversation, { 'lead_id' => new_lead_id })
    post_handoff_note(new_lead_id, conversation)
    enrich_lead(new_lead_id, conversation)
  rescue StandardError => e
    notify_sync_failure(conversation, e)
  end

  # Re-points an existing lead's salesperson when the conversation is reassigned and
  # logs the change to the lead's chatter. Only acts once a lead exists (set on Take),
  # so the assignee.changed that fires alongside the initial Take — and any pre-Take
  # idle bounce — is ignored.
  def handle_assignee_changed(conversation)
    return unless inbox_enabled?(conversation)

    lead = lead_id(conversation)
    return if lead.blank?

    fields = salesperson_fields(conversation.assignee)
    @client.execute_kw('crm.lead', 'write', [[lead], fields]) if fields.present?
    post_reassignment_note(lead, conversation.assignee)
  rescue StandardError => e
    notify_sync_failure(conversation, e)
  end

  private

  # Logs the reassignment as an internal note (mail.mt_note) on the lead's chatter so
  # Odoo users can see the salesperson was changed from the Omni conversation.
  def post_reassignment_note(lead, assignee)
    body = if assignee&.name.present?
             "Conversation reassigned to #{assignee.name} via Omni."
           else
             'Conversation unassigned via Omni.'
           end
    @client.execute_kw('crm.lead', 'message_post', [[lead]], { body: body, subtype_xmlid: 'mail.mt_note' })
  end

  # Posts the AI handoff reason (the assistant's private note on the conversation) to the
  # new lead's chatter as an internal note. The note is only written when the AI handed off
  # with a reason, so there is nothing to post otherwise.
  def post_handoff_note(lead, conversation)
    note = handoff_message(conversation)&.content
    return if note.blank?

    @client.execute_kw('crm.lead', 'message_post', [[lead]],
                       { body: "AI handoff reason: #{note}", subtype_xmlid: 'mail.mt_note' })
  end

  # The handoff note is the latest private message authored by the Jivo assistant
  # (created by Jivo::Tools::HandoffTool with the escalation reason).
  def handoff_message(conversation)
    conversation.messages
                .where(private: true, sender_type: 'JivoAssistant')
                .order(created_at: :desc)
                .first
  end

  # Best-effort: classify the lead (inquiry type + nationality/destination country) from
  # the AI handoff note via the assistant's LLM. Failures are logged and swallowed so they
  # never bubble up to the create rescue (which would email a false "sync failed").
  def enrich_lead(lead, conversation)
    message = handoff_message(conversation)
    return if message&.sender.blank?

    content = enrichment_content(message.content, conversation)
    extracted = Crm::Odoo::LeadEnrichmentService.new(assistant: message.sender, content: content).extract
    values = enrichment_write_values(extracted)
    return if values.blank?

    @client.execute_kw('crm.lead', 'write', [[lead], values])
  rescue StandardError => e
    Rails.logger.error "[ODOO] lead enrichment failed for conversation ##{conversation.id}: #{e.message}"
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
  end

  # Feed the assistant the handoff note plus the full conversation transcript so fields the
  # customer stated but the one-line note omitted (e.g. nationality) are still picked up.
  def enrichment_content(note, conversation)
    "# Handoff note\n\n#{note}\n\n# Conversation\n\n#{conversation.to_llm_text}"
  end

  # Maps the LLM extraction to crm.lead fields: inquiry_type is a selection key; nationality
  # and destination are many2one res.country, resolved from a country name to its record id.
  def enrichment_write_values(extracted)
    values = {}
    values[:inquiry_type] = extracted['inquiry_type'] if extracted['inquiry_type'].present?
    nationality_id = country_id(extracted['nationality'])
    values[:nationality_id] = nationality_id if nationality_id
    destination_id = country_id(extracted['destination'])
    values[:destination_location] = destination_id if destination_id
    values
  end

  def country_id(name)
    return if name.blank?

    @client.execute_kw('res.country', 'search', [[['name', '=ilike', name]]], { limit: 1 }).to_a.first
  end

  # Track + log the failure and email account admins with the full context so a lead
  # that fails to reach Odoo (API error, validation, uniqueness clash, …) is visible.
  def notify_sync_failure(conversation, error)
    ChatwootExceptionTracker.new(error, account: @account).capture_exception
    Rails.logger.error "Odoo lead sync failed for conversation ##{conversation.id}: #{error.message}"
    AdministratorNotifications::IntegrationsNotificationMailer
      .with(account: @account)
      .odoo_lead_sync_failed(sync_failure_meta(conversation, error))
      .deliver_later
  end

  def sync_failure_meta(conversation, error)
    {
      'conversation_display_id' => conversation.display_id,
      'inbox_name' => conversation.inbox.name,
      'contact_name' => conversation.contact&.name,
      'assignee_email' => conversation.assignee&.email,
      'error' => error.message,
      'conversation_url' => "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{@account.id}/conversations/#{conversation.display_id}"
    }
  end

  def inbox_enabled?(conversation)
    Array(@hook.settings['enabled_inbox_ids']).include?(conversation.inbox_id)
  end

  def lead_id(conversation)
    conversation.additional_attributes.dig('odoo', 'lead_id')
  end

  # Salesperson + company come from the assignee's Odoo user (matched by login/email).
  # If the agent has no Odoo user, fall back to the configured fallback salesperson so
  # the lead is always owned by a real user. Returns {} only when neither resolves
  # (Odoo then defaults the owner to the bot user).
  def salesperson_fields(assignee)
    fields = user_fields_for_login(assignee&.email)
    return fields if fields.present?

    fallback_login = @hook.settings['fallback_user_login']
    if fallback_login.present?
      Rails.logger.warn "[ODOO] assignee #{assignee&.email.inspect} has no Odoo user; assigning lead to fallback #{fallback_login}"
      fields = user_fields_for_login(fallback_login)
      return fields if fields.present?
    end

    Rails.logger.warn '[ODOO] no Odoo user matched for assignee or fallback; lead will use Odoo default owner'
    {}
  end

  def user_fields_for_login(login)
    return {} if login.blank?

    rows = @client.execute_kw('res.users', 'search_read', [[['login', '=', login]]], { fields: %w[id company_id], limit: 1 })
    user = rows.to_a.first
    return {} if user.blank?

    { user_id: user['id'], company_id: many2one_id(user['company_id']) }.compact
  end

  # The reused/created partner's current email & phone. Odoo syncs a lead's
  # email_from onto its partner on create, so we feed these back as fallbacks to
  # avoid a per-conversation placeholder overwriting an existing partner's data.
  def partner_contact_values(partner_id)
    row = @client.execute_kw('res.partner', 'read', [[partner_id]], { fields: %w[email phone] }).to_a.first || {}
    { email: row['email'].presence, phone: row['phone'].presence }
  end

  def find_or_create_partner(contact)
    stored = contact.additional_attributes.dig('external', 'odoo_partner_id')
    return stored if stored.present?

    partner_id = search_partner(contact) || create_partner(contact)
    store_external_id(contact, partner_id)
    partner_id
  end

  def search_partner(contact)
    domain = partner_search_domain(contact)
    return nil if domain.blank?

    @client.execute_kw('res.partner', 'search', [domain], { limit: 1 }).to_a.first
  end

  def partner_search_domain(contact)
    conditions = []
    conditions << ['email', '=', contact.email] if contact.email.present?
    # Search every phone representation we hold (normalized + raw); create_partner
    # may store the raw value, so searching only phone_number misses those partners
    # and Odoo's phone-uniqueness constraint then rejects the duplicate create.
    phone_search_values(contact).each { |phone| conditions << ['phone', '=', phone] }
    return [] if conditions.empty?

    # Odoo domains use prefix notation: N OR-ed leaves need N-1 leading '|'.
    Array.new(conditions.length - 1, '|') + conditions
  end

  def phone_search_values(contact)
    [contact.phone_number, contact.additional_attributes['raw_phone_number']].compact_blank.uniq
  end

  def create_partner(contact)
    data = { name: contact.name.presence || "Contact #{contact.id}" }
    data[:email] = contact.email if contact.email.present?
    phone = contact.phone_number.presence || contact.additional_attributes['raw_phone_number'].presence
    data[:phone] = phone if phone.present?

    @client.execute_kw('res.partner', 'create', [data])
  end

  # Odoo returns many2one fields as [id, display_name]; we only need the id.
  def many2one_id(value)
    value.is_a?(Array) ? value.first : value
  end

  # store_external_id in the base service keys by crm_name ('odoo'); the plan stores
  # the partner under external.odoo_partner_id, so override the key here.
  def store_external_id(contact, partner_id)
    contact.additional_attributes = {} if contact.additional_attributes.nil?
    contact.additional_attributes['external'] = {} if contact.additional_attributes['external'].blank?
    contact.additional_attributes['external']['odoo_partner_id'] = partner_id
    contact.save!
  end
end
