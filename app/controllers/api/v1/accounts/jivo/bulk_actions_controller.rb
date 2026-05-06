class Api::V1::Accounts::Jivo::BulkActionsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization
  before_action :assistant
  before_action :validate_params

  def create
    @responses = handle_assistant_responses
  end

  private

  def assistant
    @assistant = Current.account.jivo_assistants.find(params[:assistant_id])
  end

  def validate_params
    return if params[:ids].present? && params.dig(:fields, :status).present?

    render json: { success: false }, status: :unprocessable_entity
  end

  def handle_assistant_responses
    responses = @assistant.responses.where(id: params[:ids])
    return [] unless responses.exists?

    case params[:fields][:status]
    when 'approve'
      responses.pending.find_each(&:approved!)
      @assistant.responses.where(id: params[:ids]).ordered
    when 'reject', 'delete'
      responses.destroy_all
      []
    else
      []
    end
  end

  def check_authorization
    authorize(JivoAssistant)
  end
end
