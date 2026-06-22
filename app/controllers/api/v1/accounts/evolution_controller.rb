class Api::V1::Accounts::EvolutionController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def create_instance
    service = EvolutionApi::ManageService.new
    service.create_instance(
      params[:instance_name],
      params[:phone_number],
      groups_ignore: params[:groups_ignore] || false
    )
    qr_result = service.get_qrcode(params[:instance_name])

    EvolutionApi::ConnectionCheckJob.perform_later(
      account_id: Current.account.id,
      instance_name: params[:instance_name],
      user_id: Current.user.id
    )

    render json: { qrcode: qr_result.dig('base64') || qr_result.dig('qrcode', 'base64'), instance_name: params[:instance_name] }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def refresh_qr
    service = EvolutionApi::ManageService.new
    qr_result = service.get_qrcode(params[:instance_name])

    render json: { qrcode: qr_result.dig('base64') || qr_result.dig('qrcode', 'base64'), instance_name: params[:instance_name] }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def connection_status
    service = EvolutionApi::ManageService.new
    result = service.connection_state(params[:instance_name])
    state = result.dig('instance', 'state') || result['state']

    render json: { state: state, instance_name: params[:instance_name] }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def reconnect
    inbox = Current.account.inboxes.find(params[:inbox_id])
    instance_name = inbox.channel.additional_attributes['evolution_instance_name']
    raise StandardError, 'Instance not found for this inbox' if instance_name.blank?

    persist_import_settings(inbox.channel)
    service = EvolutionApi::ManageService.new
    reapply_chatwoot_config(service, inbox, instance_name)
    qr_result = service.get_qrcode(instance_name)

    EvolutionApi::ConnectionCheckJob.perform_later(
      account_id: Current.account.id,
      instance_name: instance_name,
      user_id: Current.user.id
    )

    render json: {
      qrcode: qr_result.dig('base64') || qr_result.dig('qrcode', 'base64'),
      instance_name: instance_name
    }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def complete_setup
    ActiveRecord::Base.transaction do
      channel = Current.account.api_channels.create!(
        webhook_url: evolution_webhook_url,
        additional_attributes: channel_additional_attributes
      )

      @inbox = Current.account.inboxes.create!(
        name: params[:inbox_name].presence || "WhatsApp - #{params[:phone_number]}",
        channel: channel
      )

      configure_evolution_webhook
    end

    render json: { id: @inbox.id, name: @inbox.name }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def evolution_webhook_url
    evolution_url = InstallationConfig.find_by(name: 'EVOLUTION_API_URL')&.value.presence || ''
    "#{evolution_url}/chatwoot/webhook/#{ERB::Util.url_encode(params[:instance_name])}"
  end

  def channel_additional_attributes
    {
      'evolution_api' => true,
      'evolution_instance_name' => params[:instance_name],
      'evolution_phone_number' => params[:phone_number],
      'evolution_connection_status' => 'connected',
      'evolution_import_messages' => import_messages_param,
      'evolution_days_limit_import_messages' => days_limit_param
    }
  end

  def configure_evolution_webhook
    service = EvolutionApi::ManageService.new
    service.configure_chatwoot(params[:instance_name], chatwoot_config(@inbox.name, params[:phone_number], import_options_for(@inbox.channel)))
  end

  def reapply_chatwoot_config(service, inbox, instance_name)
    phone_number = inbox.channel.additional_attributes['evolution_phone_number']
    service.configure_chatwoot(instance_name, chatwoot_config(inbox.name, phone_number, import_options_for(inbox.channel)))
  end

  def chatwoot_config(inbox_name, phone_number, import_options = {})
    {
      enabled: true,
      accountId: Current.account.id.to_s,
      token: Current.user.access_token.token,
      url: GlobalConfigService.load('FRONTEND_URL', ''),
      signMsg: false,
      reopenConversation: true,
      conversationPending: false,
      nameInbox: inbox_name,
      number: phone_number,
      autoCreate: false
    }.merge(import_options)
  end

  # Reads the message-history import settings stored on the channel so both initial
  # setup and reconnect tell Evolution to import the same number of days of history.
  def import_options_for(channel)
    import_messages = ActiveModel::Type::Boolean.new.cast(channel.additional_attributes['evolution_import_messages']) || false
    {
      importMessages: import_messages,
      daysLimitImportMessages: import_messages ? channel.additional_attributes['evolution_days_limit_import_messages'].to_i : 0
    }
  end

  # Lets users enable/adjust history import when reconnecting an existing inbox.
  def persist_import_settings(channel)
    channel.update!(
      additional_attributes: channel.additional_attributes.merge(
        'evolution_import_messages' => import_messages_param,
        'evolution_days_limit_import_messages' => days_limit_param
      )
    )
  end

  def import_messages_param
    ActiveModel::Type::Boolean.new.cast(params[:import_messages]) || false
  end

  def days_limit_param
    params[:days_limit_import_messages].to_i
  end

  def check_authorization
    authorize :inbox, :create?
  end
end
