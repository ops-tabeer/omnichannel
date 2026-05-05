class Api::V1::Accounts::Jivo::CustomToolsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization
  before_action :custom_tool, only: [:show, :update, :destroy]

  def index
    @custom_tools = Current.account.jivo_custom_tools.order(created_at: :desc)
  end

  def show; end

  def create
    @custom_tool = Current.account.jivo_custom_tools.create!(permitted_params)
  end

  def update
    @custom_tool.update!(permitted_params)
  end

  def destroy
    @custom_tool.destroy!
    head :no_content
  end

  private

  def custom_tool
    @custom_tool = Current.account.jivo_custom_tools.find(params[:id])
  end

  def permitted_params
    params.require(:custom_tool).permit(
      :title,
      :description,
      :endpoint_url,
      :http_method,
      :request_template,
      :response_template,
      :auth_type,
      :enabled,
      auth_config: {},
      param_schema: [:name, :type, :description, :required]
    )
  end

  def check_authorization
    authorize(JivoCustomTool)
  end
end
