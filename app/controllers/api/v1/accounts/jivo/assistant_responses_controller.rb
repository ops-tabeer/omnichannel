class Api::V1::Accounts::Jivo::AssistantResponsesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization
  before_action :assistant
  before_action :assistant_response, only: [:show, :update, :destroy]

  def index
    scope = @assistant.responses.ordered
    scope = scope.where(status: params[:status]) if params[:status].present?
    @responses = scope
  end

  def show; end

  def create
    @response = @assistant.responses.create!(permitted_params.merge(status: :approved))
  end

  def update
    @response.update!(permitted_params)
  end

  def destroy
    @response.destroy!
    head :ok
  end

  private

  def assistant
    @assistant = Current.account.jivo_assistants.find(params[:assistant_id])
  end

  def assistant_response
    @response = @assistant.responses.find(params[:id])
  end

  def permitted_params
    params.require(:assistant_response).permit(:question, :answer, :status)
  end

  def check_authorization
    authorize(JivoAssistant)
  end
end
