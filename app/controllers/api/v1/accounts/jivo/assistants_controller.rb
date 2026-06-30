class Api::V1::Accounts::Jivo::AssistantsController < Api::V1::Accounts::BaseController
  include Jivo::FeatureGated

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

  def playground
    if @assistant.effective_openai_api_key.blank?
      render json: { response: I18n.t('jivo.playground.openai_key_missing'), reasoning: 'OpenAI API key not configured' }
      return
    end

    response = Jivo::Assistant::AgentRunnerService.new(assistant: @assistant).generate_response(message_history: playground_history)
    render json: response
  end

  private

  def playground_history
    Array(params[:message_history]).map { |msg| { role: msg[:role].to_s, content: msg[:content].to_s } }
                                   .reject { |msg| msg[:content].blank? }
                                   .tap do |history|
      history << { role: 'user', content: params[:message_content].to_s } if params[:message_content].present?
    end
  end

  def assistant
    @assistant = Current.account.jivo_assistants.find(params[:id])
  end

  def permitted_params
    attrs = params.require(:assistant).permit(
      :name,
      :description,
      response_guidelines: [],
      guardrails: [],
      config: [:openai_api_key, :openai_model, :system_prompt, :handoff_message, :temperature, :product_name,
               :feature_memory, :feature_faq, :feature_idle_action, :idle_timeout_minutes, :idle_action, :idle_message,
               :idle_reminder_limit, :feature_v2_agent, :feature_citation, :on_limit_action,
               :idle_use_ai, :idle_prompt]
    )
    config_attrs = attrs[:config]
    config_attrs&.delete(:openai_api_key) if config_attrs && (!Current.account.jivo_byo_key_allowed || config_attrs[:openai_api_key].blank?)
    attrs
  end

  def check_authorization
    authorize(JivoAssistant)
  end
end
