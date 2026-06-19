class AdministratorNotifications::IntegrationsNotificationMailer < AdministratorNotifications::BaseMailer
  def slack_disconnect
    subject = 'Your Slack integration has expired'
    action_url = settings_url('integrations/slack')
    send_notification(subject, action_url: action_url)
  end

  def dialogflow_disconnect
    subject = 'Your Dialogflow integration was disconnected'
    send_notification(subject)
  end

  ODOO_SYNC_FAILURE_RECIPIENT = 'kamran@tabeertours.com'.freeze

  def odoo_lead_sync_failed(meta)
    subject = "A lead failed to sync to Odoo CRM (conversation ##{meta['conversation_display_id']})"
    send_notification(subject, to: ODOO_SYNC_FAILURE_RECIPIENT, action_url: meta['conversation_url'], meta: meta)
  end

  # Notifies the lead recipient (assignee, or the fallback salesperson) that their Odoo CRM
  # lead was created, with a deep link to it. Skips entirely when no specific recipient
  # resolves, so it never falls back to emailing all account admins.
  def odoo_lead_created(meta)
    return if meta['assignee_email'].blank?

    subject = "A new lead was created in Odoo CRM (conversation ##{meta['conversation_display_id']})"
    send_notification(subject, to: meta['assignee_email'], action_url: meta['lead_url'], meta: meta)
  end
end
