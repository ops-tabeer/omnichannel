# == Schema Information
#
# Table name: jivo_assistants
#
#  id                  :bigint           not null, primary key
#  config              :jsonb            not null
#  description         :text
#  guardrails          :jsonb
#  name                :string           not null
#  response_guidelines :jsonb
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#
# Indexes
#
#  index_jivo_assistants_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
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
  has_one_attached :avatar

  AVATAR_MAX_BYTES = 2.megabytes

  validates :name, presence: true
  validates :description, presence: true
  validate :avatar_size_within_limit

  store_accessor :config, :openai_api_key, :openai_model, :system_prompt, :handoff_message, :temperature, :product_name,
                 :feature_memory, :feature_faq, :feature_idle_action, :idle_timeout_minutes, :idle_action, :idle_message,
                 :idle_reminder_limit, :feature_v2_agent, :feature_citation, :idle_action_enabled_at

  # System-managed cutoff: stamp the moment the idle action is switched on so the job
  # only ever acts on conversations created after enabling (never the pre-enable backlog).
  before_save :stamp_idle_action_enabled_at

  IDLE_ACTION_HANDOFF = 'handoff'.freeze
  IDLE_ACTION_RESOLVE = 'resolve'.freeze
  IDLE_ACTION_REMINDER = 'reminder'.freeze
  IDLE_ACTIONS = [IDLE_ACTION_HANDOFF, IDLE_ACTION_RESOLVE, IDLE_ACTION_REMINDER].freeze
  DEFAULT_IDLE_TIMEOUT_MINUTES = 60
  DEFAULT_IDLE_REMINDER_LIMIT = 3

  NON_VISION_MODEL_PATTERNS = [
    /\Agpt-3\.5/i,
    /\Atext-/i,
    /\Ao1-mini/i,
    /\Agpt-4-0314/i,
    /\Agpt-4-0613/i,
    /-instruct\z/i,
    /-nano\b/i
  ].freeze

  def model
    openai_model.presence || 'gpt-4.1-mini'
  end

  def effective_openai_api_key
    return openai_api_key if account.jivo_byo_key_allowed && openai_api_key.present?

    InstallationConfig.find_by(name: 'JIVO_OPEN_AI_API_KEY')&.value
  end

  def vision_capable?
    NON_VISION_MODEL_PATTERNS.none? { |pattern| pattern.match?(model) }
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
    ActiveModel::Type::Boolean.new.cast(account.jivo_v2_agent) ||
      ActiveModel::Type::Boolean.new.cast(feature_v2_agent)
  end

  def feature_citation_enabled?
    ActiveModel::Type::Boolean.new.cast(feature_citation)
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

  def idle_action_enabled_at_value
    return if idle_action_enabled_at.blank?

    Time.zone.parse(idle_action_enabled_at.to_s)
  rescue ArgumentError
    nil
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

  # Stamp the cutoff only on a false->true transition of feature_idle_action, so
  # re-enabling later restarts the window and other config edits don't touch it.
  def stamp_idle_action_enabled_at
    return unless will_save_change_to_config?

    old_config, new_config = changes_to_save['config']
    was_enabled = ActiveModel::Type::Boolean.new.cast(old_config&.dig('feature_idle_action'))
    now_enabled = ActiveModel::Type::Boolean.new.cast(new_config&.dig('feature_idle_action'))
    return unless now_enabled && !was_enabled

    self.idle_action_enabled_at = Time.current.iso8601
  end

  def avatar_size_within_limit
    return unless avatar.attached?
    return if avatar.byte_size <= AVATAR_MAX_BYTES

    errors.add(:avatar, "is too large (max #{AVATAR_MAX_BYTES / 1.megabyte} MB)")
  end

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
