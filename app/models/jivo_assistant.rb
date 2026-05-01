# == Schema Information
#
# Table name: jivo_assistants
#
#  id          :bigint           not null, primary key
#  config      :jsonb            not null, default: {}
#  description :text
#  name        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#

class JivoAssistant < ApplicationRecord
  belongs_to :account
  has_many :jivo_inboxes, dependent: :destroy_async
  has_many :inboxes, through: :jivo_inboxes
  has_many :messages, as: :sender, dependent: :nullify
  has_many :documents, class_name: 'JivoDocument', dependent: :destroy_async
  has_many :responses, class_name: 'JivoAssistantResponse', dependent: :destroy_async

  validates :name, presence: true
  validates :description, presence: true

  store_accessor :config, :openai_api_key, :openai_model, :system_prompt, :handoff_message, :temperature, :product_name

  def model
    openai_model.presence || 'gpt-4.1-mini'
  end

  def temperature_value
    temperature.to_f.zero? ? 0.7 : temperature.to_f
  end

  def handoff_message_text
    handoff_message.presence || I18n.t('conversations.jivo.handoff', default: 'Connecting you to a human agent.')
  end

  def available_name
    name
  end

  def push_event_data
    {
      id: id,
      name: name,
      type: 'jivo_assistant'
    }
  end
end
