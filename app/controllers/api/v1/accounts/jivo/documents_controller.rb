class Api::V1::Accounts::Jivo::DocumentsController < Api::V1::Accounts::BaseController
  include Jivo::FeatureGated

  before_action :current_account
  before_action :check_authorization
  before_action :assistant
  before_action :document, only: [:show, :destroy, :recrawl]

  def index
    @documents = @assistant.documents.order(created_at: :desc)
  end

  def show; end

  def create
    @document = @assistant.documents.create!(permitted_params)
  end

  def destroy
    @document.destroy!
    head :ok
  end

  def recrawl
    @document.jivo_assistant_responses.destroy_all
    @document.update!(status: :in_progress)
    Jivo::Documents::CrawlJob.perform_later(@document)
    render :show
  end

  private

  def assistant
    @assistant = Current.account.jivo_assistants.find(params[:assistant_id])
  end

  def document
    @document = @assistant.documents.find(params[:id])
  end

  def permitted_params
    params.require(:document).permit(:name, :external_link, :file)
  end

  def check_authorization
    authorize(JivoAssistant)
  end
end
