# == Schema Information
#
# Table name: jivo_scenarios
#
#  id                :bigint           not null, primary key
#  description       :text
#  enabled           :boolean          default(TRUE), not null
#  instruction       :text
#  title             :string
#  tools             :jsonb
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  jivo_assistant_id :bigint           not null
#
# Indexes
#
#  index_jivo_scenarios_on_account_id                     (account_id)
#  index_jivo_scenarios_on_enabled                        (enabled)
#  index_jivo_scenarios_on_jivo_assistant_id              (jivo_assistant_id)
#  index_jivo_scenarios_on_jivo_assistant_id_and_enabled  (jivo_assistant_id,enabled)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (jivo_assistant_id => jivo_assistants.id)
#

class JivoScenario < ApplicationRecord
  include JivoToolsHelpers
  include JivoAgentable

  TOOL_REFERENCE_REGEX = JivoToolsHelpers::TOOL_REFERENCE_REGEX

  belongs_to :jivo_assistant
  belongs_to :account

  delegate :temperature_value, :openai_api_key, :model, to: :jivo_assistant

  validates :title, presence: true
  validates :description, presence: true
  validates :instruction, presence: true
  validate :validate_instruction_tools

  scope :enabled, -> { where(enabled: true) }

  before_save :extract_tool_refs

  def agent_name
    "#{title} Agent".parameterize(separator: '_')
  end

  def agent_tool_instances
    tools.to_a.filter_map { |tool_id| resolve_tool_instance(tool_id, jivo_assistant) }
  end

  def agent_model
    model
  end

  def agent_instructions(context = nil)
    state = context&.context&.dig(:state) || {}
    Jivo::Prompts::ScenarioPrompt.new(scenario: self, state: state).render
  end

  private

  def extract_tool_refs
    extracted = instruction.to_s.scan(TOOL_REFERENCE_REGEX).flatten
    self.tools = (Array(tools) + extracted).map(&:to_s).reject(&:blank?).uniq
  end

  def validate_instruction_tools
    return if instruction.blank?

    referenced = instruction.scan(TOOL_REFERENCE_REGEX).flatten.uniq
    return if referenced.blank?

    invalid = referenced - jivo_assistant.available_tool_ids
    return if invalid.empty?

    errors.add(:instruction, "references unknown tools: #{invalid.join(', ')}")
  end
end
