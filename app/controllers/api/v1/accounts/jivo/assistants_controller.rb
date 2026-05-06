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

  def avatar
    return head :unprocessable_entity if params[:avatar].blank?

    @assistant.avatar.attach(params[:avatar])
    @assistant.save!
    render :show
  end

  def remove_avatar
    @assistant.avatar.purge if @assistant.avatar.attached?
    render :show
  end

  private

  def assistant
    @assistant = Current.account.jivo_assistants.find(params[:id])
  end

  def permitted_params
    params.require(:assistant).permit(
      :name,
      :description,
      response_guidelines: [],
      guardrails: [],
      config: [:openai_api_key, :openai_model, :system_prompt, :handoff_message, :temperature, :product_name,
               :feature_memory, :feature_faq, :feature_idle_action, :idle_timeout_minutes, :idle_action, :idle_message,
               :idle_reminder_limit, :feature_v2_agent]
    )
  end

  def check_authorization
    authorize(JivoAssistant)
  end
end
