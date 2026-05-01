class Api::V1::Accounts::Jivo::AssistantsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization
  before_action :assistant, except: [:index, :create]

  def index
    @assistants = Current.account.jivo_assistants.order(created_at: :desc)
  end

  def show; end

  def create
    @assistant = Current.account.jivo_assistants.create!(permitted_params)
  end

  def update
    @assistant.update!(permitted_params)
  end

  def destroy
    @assistant.destroy!
    head :ok
  end

  private

  def assistant
    @assistant = Current.account.jivo_assistants.find(params[:id])
  end

  def permitted_params
    params.require(:assistant).permit(
      :name,
      :description,
      config: [:openai_api_key, :openai_model, :system_prompt, :handoff_message, :temperature, :product_name]
    )
  end

  def check_authorization
    authorize(JivoAssistant)
  end
end
