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
  include JivoToolsHelpers
  include JivoAgentable

  belongs_to :account
  has_many :jivo_inboxes, dependent: :destroy_async
  has_many :inboxes, through: :jivo_inboxes
  has_many :messages, as: :sender, dependent: :nullify
  has_many :documents, class_name: 'JivoDocument', dependent: :destroy_async
  has_many :responses, class_name: 'JivoAssistantResponse', dependent: :destroy_async
  has_many :scenarios, class_name: 'JivoScenario', dependent: :destroy_async

  validates :name, presence: true
  validates :description, presence: true

  store_accessor :config, :openai_api_key, :openai_model, :system_prompt, :handoff_message, :temperature, :product_name,
                 :feature_memory, :feature_faq, :feature_idle_action, :idle_timeout_minutes, :idle_action, :idle_message,
                 :idle_reminder_limit, :feature_v2_agent

  IDLE_ACTION_HANDOFF = 'handoff'.freeze
  IDLE_ACTION_RESOLVE = 'resolve'.freeze
  IDLE_ACTION_REMINDER = 'reminder'.freeze
  IDLE_ACTIONS = [IDLE_ACTION_HANDOFF, IDLE_ACTION_RESOLVE, IDLE_ACTION_REMINDER].freeze
  DEFAULT_IDLE_TIMEOUT_MINUTES = 60
  DEFAULT_IDLE_REMINDER_LIMIT = 3

  def model
    openai_model.presence || 'gpt-4.1-mini'
  end

  def temperature_value
    temperature.to_f.zero? ? 0.7 : temperature.to_f
  end

  def handoff_message_text
    handoff_message.presence || I18n.t('conversations.jivo.handoff', default: 'Connecting you to a human agent.')
  end

  def idle_action_enabled?
    ActiveModel::Type::Boolean.new.cast(feature_idle_action)
  end

  def feature_v2_agent_enabled?
    ActiveModel::Type::Boolean.new.cast(feature_v2_agent)
  end

  def idle_timeout_minutes_value
    idle_timeout_minutes.to_i.positive? ? idle_timeout_minutes.to_i : DEFAULT_IDLE_TIMEOUT_MINUTES
  end

  def idle_action_value
    IDLE_ACTIONS.include?(idle_action) ? idle_action : IDLE_ACTION_HANDOFF
  end

  def idle_message_text
    idle_message.presence || default_idle_message
  end

  def idle_reminder_limit_value
    idle_reminder_limit.to_i.positive? ? idle_reminder_limit.to_i : DEFAULT_IDLE_REMINDER_LIMIT
  end

  def available_name
    name
  end

  def available_agent_tools
    tools = self.class.built_in_agent_tools.dup
    tools.concat(account.jivo_custom_tools.enabled.map(&:to_tool_metadata))
    tools
  end

  def available_tool_ids
    available_agent_tools.pluck(:id)
  end

  def agent_name
    name.presence || 'JIVO Assistant'
  end

  def agent_tool_instances
    available_tool_ids.filter_map { |tool_id| resolve_tool_instance(tool_id, self) }
  end

  def agent_model
    model
  end

  def agent_instructions(context = nil)
    state = context&.context&.dig(:state) || {}
    Jivo::Prompts::AssistantPrompt.new(
      assistant: self,
      state: state
    ).render
  end

  def push_event_data
    {
      id: id,
      name: name,
      type: 'jivo_assistant'
    }
  end

  private

  def default_idle_message
    case idle_action_value
    when IDLE_ACTION_RESOLVE
      I18n.t('conversations.jivo.idle_resolve', default: I18n.t('conversations.activity.auto_resolution_message'))
    when IDLE_ACTION_REMINDER
      I18n.t('conversations.jivo.idle_reminder',
             default: 'Just checking in. Please reply when you are ready to continue.')
    else
      handoff_message_text
    end
  end
end
