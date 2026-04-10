class EvolutionApi::SyncConnectionStatusJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Channel::Api.where("additional_attributes->>'evolution_api' = 'true'").find_each do |channel|
      instance_name = channel.additional_attributes['evolution_instance_name']
      next if instance_name.blank?

      sync_status(channel, instance_name)
    end
  end

  private

  def sync_status(channel, instance_name)
    service = EvolutionApi::ManageService.new
    result = service.connection_state(instance_name)
    Rails.logger.info("[EvolutionAPI] Raw response for #{instance_name}: #{result.inspect}")
    state = result.dig('instance', 'state') || result['state']
    Rails.logger.info("[EvolutionAPI] Parsed state for #{instance_name}: #{state.inspect}")
    status = state == 'open' ? 'connected' : 'disconnected'

    channel.update!(
      additional_attributes: channel.additional_attributes.merge('evolution_connection_status' => status)
    )
  rescue StandardError => e
    Rails.logger.error("[EvolutionAPI] Failed to sync status for #{instance_name}: #{e.message}")
  end
end
