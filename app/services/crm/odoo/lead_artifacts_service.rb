# Adds the post-create artifacts to a freshly created Odoo lead from the handed-off
# conversation: the AI handoff note, the AI field enrichment, and the conversation summary.
# Enrichment and summary are best-effort (errors logged and swallowed); a handoff-note
# failure propagates so the caller can surface it as a sync failure.
class Crm::Odoo::LeadArtifactsService
  def initialize(client, account)
    @client = client
    @account = account
  end

  def apply(lead, conversation)
    message = handoff_message(conversation)
    post_handoff_note(lead, message)
    enrich_lead(lead, conversation, message)
    summarize_lead(lead, conversation, message)
  end

  private

  # The handoff note is the latest private message authored by the Jivo assistant
  # (created by Jivo::Tools::HandoffTool with the escalation reason).
  def handoff_message(conversation)
    conversation.messages
                .where(private: true, sender_type: 'JivoAssistant')
                .order(created_at: :desc)
                .first
  end

  def post_handoff_note(lead, message)
    note = message&.content
    return if note.blank?

    @client.execute_kw('crm.lead', 'message_post', [[lead]],
                       { body: "AI handoff reason: #{note}", subtype_xmlid: 'mail.mt_note' })
  end

  # Best-effort: classify the lead (inquiry type + nationality/destination country) from the
  # handoff note + conversation transcript via the assistant's LLM.
  def enrich_lead(lead, conversation, message)
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

  # Best-effort: generate the same conversation summary as the JIVO summary feature and add
  # it to the lead — rich markup in the Notes (description html field) and a clean plaintext
  # copy in the chatter. The JIVO summary is markdown; Odoo's message_post plaintext-escapes
  # any HTML, so the chatter gets stripped plaintext while Notes keeps the rendered HTML.
  def summarize_lead(lead, conversation, message)
    return if message&.sender.blank?

    result = Jivo::Tasks::SummarizeService.new(assistant: message.sender, conversation: conversation).perform
    return unless result[:success] && result[:message].present?

    renderer = ChatwootMarkdownRenderer.new(result[:message])
    @client.execute_kw('crm.lead', 'write', [[lead], { description: renderer.render_message.to_s }])
    @client.execute_kw('crm.lead', 'message_post', [[lead]],
                       { body: renderer.render_markdown_to_plain_text, subtype_xmlid: 'mail.mt_note' })
  rescue StandardError => e
    Rails.logger.error "[ODOO] lead summary failed for conversation ##{conversation.id}: #{e.message}"
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
  end
end
