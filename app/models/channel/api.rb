# == Schema Information
#
# Table name: channel_api
#
#  id                    :bigint           not null, primary key
#  additional_attributes :jsonb
#  hmac_mandatory        :boolean          default(FALSE)
#  hmac_token            :string
#  identifier            :string
#  webhook_url           :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :integer          not null
#
# Indexes
#
#  index_channel_api_on_hmac_token  (hmac_token) UNIQUE
#  index_channel_api_on_identifier  (identifier) UNIQUE
#

class Channel::Api < ApplicationRecord
  include Channelable

  self.table_name = 'channel_api'
  EDITABLE_ATTRS = [:webhook_url, :hmac_mandatory, { additional_attributes: {} }].freeze

  has_secure_token :identifier
  has_secure_token :hmac_token
  validate :ensure_valid_agent_reply_time_window
  validates :webhook_url, length: { maximum: Limits::URL_LENGTH_LIMIT }
  after_destroy :cleanup_evolution_instance

  def name
    'API'
  end

  private

  def cleanup_evolution_instance
    return unless additional_attributes&.dig('evolution_api')

    instance_name = additional_attributes['evolution_instance_name']
    return if instance_name.blank?

    EvolutionApi::ManageService.new.delete_instance(instance_name)
  rescue StandardError => e
    Rails.logger.error("[EvolutionAPI] Failed to delete instance #{instance_name}: #{e.message}")
  end

  def ensure_valid_agent_reply_time_window
    return if additional_attributes['agent_reply_time_window'].blank?
    return if additional_attributes['agent_reply_time_window'].to_i.positive?

    errors.add(:agent_reply_time_window, 'agent_reply_time_window must be greater than 0')
  end
end
