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
    notify_lead_created(conversation, new_lead_id)
    Crm::Odoo::LeadArtifactsService.new(@client, @account).apply(new_lead_id, conversation)
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

  # Syncs a linked contact's real email/phone onto its Odoo partner when the contact is
  # updated (manually or by AI enrichment). A field is skipped when its value is already
  # used by another partner, so Odoo's email/phone uniqueness constraint never trips. The
  # lead's email/phone follow the partner in Odoo, so we only touch the partner. Best-effort.
  def handle_contact_updated(contact)
    partner_id = contact.additional_attributes.dig('external', 'odoo_partner_id')
    return if partner_id.blank?

    current = @client.execute_kw('res.partner', 'read', [[partner_id]], { fields: %w[email phone] }).to_a.first || {}
    values = {}
    add_partner_value(values, :email, contact.email.presence, current['email'], partner_id)
    add_partner_value(values, :phone, contact_phone(contact), current['phone'], partner_id)
    return if values.blank?

    @client.execute_kw('res.partner', 'write', [[partner_id], values])
  rescue StandardError => e
    Rails.logger.error "[ODOO] contact sync failed for contact ##{contact.id}: #{e.message}"
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
  end

  private

  def contact_phone(contact)
    contact.phone_number.presence || contact.additional_attributes['raw_phone_number'].presence
  end

  # Adds field => new_value to the partner write only when it actually changed and the value
  # isn't already taken by another Odoo partner (the uniqueness guard).
  def add_partner_value(values, field, new_value, current_value, partner_id)
    return if new_value.blank? || new_value == current_value
    return if partner_field_taken?(field, new_value, partner_id)

    values[field] = new_value
  end

  def partner_field_taken?(field, value, partner_id)
    @client.execute_kw('res.partner', 'search',
                       [[[field.to_s, '=', value], ['id', '!=', partner_id]]], { limit: 1 }).to_a.any?
  end

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

  # Emails the lead recipient (assignee, or the fallback salesperson when the conversation
  # has no assignee) that their Odoo CRM lead was created, with a deep link to it.
  def notify_lead_created(conversation, lead_id)
    AdministratorNotifications::IntegrationsNotificationMailer
      .with(account: @account)
      .odoo_lead_created(lead_created_meta(conversation, lead_id))
      .deliver_later
  end

  def lead_created_meta(conversation, lead_id)
    {
      'conversation_display_id' => conversation.display_id,
      'inbox_name' => conversation.inbox.name,
      'contact_name' => conversation.contact&.name,
      # Recipient: the assignee, else the configured fallback salesperson (who owns the lead
      # in Odoo when there is no assignee). Falls back to account admins when both are blank.
      'assignee_email' => conversation.assignee&.email || @hook.settings['fallback_user_login'].presence,
      'lead_url' => "#{@hook.settings['url'].to_s.chomp('/')}/odoo/crm/#{lead_id}",
      'conversation_url' => "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{@account.id}/conversations/#{conversation.display_id}"
    }
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

    rows = @client.execute_kw('res.users', 'search_read', [[['login', '=ilike', login]]], { fields: %w[id company_id], limit: 1 })
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
