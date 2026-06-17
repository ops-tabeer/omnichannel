class Api::V1::Accounts::Jivo::ScenariosController < Api::V1::Accounts::BaseController
  include Jivo::FeatureGated

  before_action :current_account
  before_action :check_authorization
  before_action :assistant
  before_action :scenario, only: [:show, :update, :destroy]

  def index
    @scenarios = @assistant.scenarios.order(created_at: :desc)
  end

  def show; end

  def create
    @scenario = @assistant.scenarios.create!(permitted_params.merge(account: Current.account))
  end

  def update
    @scenario.update!(permitted_params)
  end

  def destroy
    @scenario.destroy!
    head :no_content
  end

  private

  def assistant
    @assistant = Current.account.jivo_assistants.find(params[:assistant_id])
  end

  def scenario
    @scenario = @assistant.scenarios.find(params[:id])
  end

  def permitted_params
    params.require(:scenario).permit(:title, :description, :instruction, :enabled, tools: [])
  end

  def check_authorization
    authorize(JivoScenario)
  end
end
