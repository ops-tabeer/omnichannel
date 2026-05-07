class Api::V1::Accounts::Jivo::TasksController < Api::V1::Accounts::BaseController
  include Jivo::FeatureGated

  before_action :current_account
  before_action :check_authorization
  before_action :load_assistant

  def rewrite
    result = Jivo::Tasks::RewriteService.new(
      assistant: @assistant,
      content: params[:content],
      operation: params[:operation],
      conversation: load_conversation
    ).perform

    render json: result
  end

  def summarize
    conversation = load_conversation!
    result = Jivo::Tasks::SummarizeService.new(
      assistant: @assistant,
      conversation: conversation
    ).perform

    render json: result
  end

  def reply_suggestion
    conversation = load_conversation!
    result = Jivo::Tasks::ReplySuggestionService.new(
      assistant: @assistant,
      conversation: conversation,
      agent: Current.user
    ).perform

    render json: result
  end

  def label_suggestion
    conversation = load_conversation!
    result = Jivo::Tasks::LabelSuggestionService.new(
      assistant: @assistant,
      conversation: conversation
    ).perform

    render json: result
  end

  def follow_up
    result = Jivo::Tasks::FollowUpService.new(
      assistant: @assistant,
      follow_up_context: params[:follow_up_context]&.to_unsafe_h,
      message: params[:message]
    ).perform

    render json: result
  end

  def learn_from_conversation
    authorize(JivoAssistant, :learn_from_conversation?)
    conversation = load_conversation!

    Jivo::ContactNotesJob.perform_later(conversation, @assistant)
    Jivo::ConversationFaqJob.perform_later(conversation, @assistant, force: true)

    render json: { success: true, message: I18n.t('jivo.tasks.learn.queued') }
  end

  private

  def load_assistant
    @assistant = if params[:assistant_id].present?
                   Current.account.jivo_assistants.find(params[:assistant_id])
                 elsif params[:conversation_display_id].present?
                   load_conversation&.inbox&.jivo_assistant || Current.account.jivo_assistants.order(:id).first
                 else
                   Current.account.jivo_assistants.order(:id).first
                 end

    return if @assistant.present?

    render json: { success: false, error: 'No JIVO assistant configured for this account' },
           status: :unprocessable_entity
  end

  def load_conversation
    return nil if params[:conversation_display_id].blank?

    @conversation ||= Current.account.conversations.find_by(display_id: params[:conversation_display_id])
    authorize(@conversation, :show?) if @conversation.present?
    @conversation
  end

  def load_conversation!
    conv = load_conversation
    raise ActiveRecord::RecordNotFound, 'Conversation not found' if conv.blank?

    conv
  end

  def check_authorization
    authorize(JivoAssistant)
  end
end
