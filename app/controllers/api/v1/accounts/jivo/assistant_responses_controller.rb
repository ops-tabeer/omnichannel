class Api::V1::Accounts::Jivo::AssistantResponsesController < Api::V1::Accounts::BaseController
  include Jivo::FeatureGated

  before_action :current_account
  before_action :check_authorization
  before_action :assistant
  before_action :set_current_page, only: [:index]
  before_action :assistant_response, only: [:show, :update, :destroy]

  RESULTS_PER_PAGE = 10

  def index
    scope = @assistant.responses.ordered
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = search_scope(scope) if params[:query].present?
    @responses_count = scope.count
    @responses = scope.page(@current_page).per(RESULTS_PER_PAGE)
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

  def set_current_page
    @current_page = params[:page].presence || 1
  end

  def permitted_params
    params.require(:assistant_response).permit(:question, :answer, :status)
  end

  def search_scope(scope)
    query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:query].to_s.strip)}%"
    scope.where('question ILIKE :query OR answer ILIKE :query', query: query)
  end

  def check_authorization
    authorize(JivoAssistant)
  end
end
