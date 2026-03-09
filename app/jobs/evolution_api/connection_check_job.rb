class EvolutionApi::ConnectionCheckJob < ApplicationJob
  include Events::Types

  queue_as :default

  MAX_ATTEMPTS = 60
  POLL_INTERVAL = 3.seconds

  def perform(account_id:, instance_name:, user_id:, attempt: 1)
    return if attempt > MAX_ATTEMPTS

    service = EvolutionApi::ManageService.new
    result = service.connection_state(instance_name)
    state = result.dig('instance', 'state') || result['state']

    if state == 'open'
      broadcast_connected(account_id, instance_name, user_id)
    else
      self.class.set(wait: POLL_INTERVAL).perform_later(
        account_id: account_id,
        instance_name: instance_name,
        user_id: user_id,
        attempt: attempt + 1
      )
    end
  rescue StandardError => e
    Rails.logger.error("[EvolutionAPI] Connection check failed for #{instance_name}: #{e.message}")
  end

  private

  def broadcast_connected(account_id, instance_name, user_id)
    account = Account.find(account_id)
    user = User.find(user_id)

    Rails.configuration.dispatcher.dispatch(
      EVOLUTION_CONNECTED,
      Time.zone.now,
      account: account,
      user: user,
      instance_name: instance_name
    )
  end
end
