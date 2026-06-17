class Jivo::ProcessConversationJob < ApplicationJob
  queue_as :high

  retry_on Net::ReadTimeout, attempts: 3, wait: 2.seconds
  retry_on Net::OpenTimeout, attempts: 3, wait: 2.seconds

  def perform(conversation, assistant)
    return unless conversation.pending?
    return unless conversation.inbox.active_jivo_assistant?

    Jivo::ConversationHandlerService.new(
      conversation: conversation,
      assistant: assistant
    ).perform
  end
end
