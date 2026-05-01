class Api::V1::Accounts::Jivo::InboxesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization
  before_action :assistant

  def index
    @inboxes = @assistant.inboxes
  end

  def create
    inbox = Current.account.inboxes.find(params[:inbox_id])
    @jivo_inbox = JivoInbox.create!(jivo_assistant: @assistant, inbox: inbox)
    @inboxes = @assistant.inboxes.reload
    render :index
  end

  def destroy
    inbox = Current.account.inboxes.find(params[:inbox_id])
    JivoInbox.where(jivo_assistant: @assistant, inbox: inbox).destroy_all
    head :ok
  end

  private

  def assistant
    @assistant = Current.account.jivo_assistants.find(params[:assistant_id])
  end

  def check_authorization
    authorize(JivoAssistant)
  end
end
