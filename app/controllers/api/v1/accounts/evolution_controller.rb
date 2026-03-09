class Api::V1::Accounts::EvolutionController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def create_instance
    service = EvolutionApi::ManageService.new
    service.create_instance(params[:instance_name], params[:phone_number])
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

  def complete_setup
    ActiveRecord::Base.transaction do
      evolution_url = InstallationConfig.find_by(name: 'EVOLUTION_API_URL')&.value.presence || ''
      channel = Current.account.api_channels.create!(
        webhook_url: "#{evolution_url}/chatwoot/webhook/#{ERB::Util.url_encode(params[:instance_name])}",
        additional_attributes: {
          'evolution_api' => true,
          'evolution_instance_name' => params[:instance_name],
          'evolution_phone_number' => params[:phone_number]
        }
      )

      @inbox = Current.account.inboxes.create!(
        name: params[:inbox_name].presence || "WhatsApp - #{params[:phone_number]}",
        channel: channel
      )

      configure_evolution_webhook(channel)
    end

    render json: { id: @inbox.id, name: @inbox.name }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def configure_evolution_webhook(channel)
    frontend_url = GlobalConfigService.load('FRONTEND_URL', '')
    service = EvolutionApi::ManageService.new

    service.configure_chatwoot(
      params[:instance_name],
      {
        enabled: true,
        accountId: Current.account.id.to_s,
        token: Current.user.access_token.token,
        url: frontend_url,
        signMsg: true,
        reopenConversation: true,
        conversationPending: false,
        nameInbox: @inbox.name,
        number: params[:phone_number],
        autoCreate: false
      }
    )
  end

  def check_authorization
    authorize :inbox, :create?
  end
end
