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
                 :idle_reminder_limit, :feature_v2_agent, :feature_citation, :idle_action_enabled_at,
                 :on_limit_action, :idle_use_ai, :idle_prompt

  # System-managed cutoff: stamp the moment the idle action is switched on so the job
  # only ever acts on conversations created after enabling (never the pre-enable backlog).
  before_save :stamp_idle_action_enabled_at

  IDLE_ACTION_HANDOFF = 'handoff'.freeze
  DEFAULT_IDLE_TIMEOUT_MINUTES = 60
  DEFAULT_IDLE_REMINDER_LIMIT = 3

  # What to do once the follow-up attempts are exhausted (no auto-resolve).
  ON_LIMIT_ACTION_NONE = 'none'.freeze
  ON_LIMIT_ACTIONS = [IDLE_ACTION_HANDOFF, ON_LIMIT_ACTION_NONE].freeze
  DEFAULT_ON_LIMIT_ACTION = IDLE_ACTION_HANDOFF

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

  def idle_use_ai_enabled?
    ActiveModel::Type::Boolean.new.cast(idle_use_ai)
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

  def idle_message_text
    idle_message.presence || default_idle_message
  end

  def idle_reminder_limit_value
    idle_reminder_limit.to_i.positive? ? idle_reminder_limit.to_i : DEFAULT_IDLE_REMINDER_LIMIT
  end

  # Escalation after the follow-up limit is hit: handoff (default) or none.
  def on_limit_action_value
    ON_LIMIT_ACTIONS.include?(on_limit_action) ? on_limit_action : DEFAULT_ON_LIMIT_ACTION
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

  # Manage the system-owned cutoff. Stamp fresh only on a false->true transition of
  # feature_idle_action (re-enabling restarts the window). The Settings form replaces the
  # whole config without this key, so when it's still enabled, carry the existing value
  # forward instead of letting an unrelated save wipe it.
  def stamp_idle_action_enabled_at
    return unless will_save_change_to_config?

    old_config, new_config = changes_to_save['config']

    if idle_action_just_enabled?(old_config, new_config)
      self.idle_action_enabled_at = Time.current.iso8601
    elsif idle_action_enabled_at.blank?
      self.idle_action_enabled_at = old_config&.dig('idle_action_enabled_at')
    end
  end

  def idle_action_just_enabled?(old_config, new_config)
    config_flag(new_config, 'feature_idle_action') && !config_flag(old_config, 'feature_idle_action')
  end

  def config_flag(config_hash, key)
    ActiveModel::Type::Boolean.new.cast(config_hash&.dig(key))
  end

  def avatar_size_within_limit
    return unless avatar.attached?
    return if avatar.byte_size <= AVATAR_MAX_BYTES

    errors.add(:avatar, "is too large (max #{AVATAR_MAX_BYTES / 1.megabyte} MB)")
  end

  # The follow-up is always a check-in nudge now; escalation (handoff/resolve) is a
  # separate step after the limit, so the default message is the reminder text.
  def default_idle_message
    I18n.t('conversations.jivo.idle_reminder',
           default: 'Just checking in. Please reply when you are ready to continue.')
  end
end
