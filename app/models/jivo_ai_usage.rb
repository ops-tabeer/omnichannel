# == Schema Information
#
# Table name: jivo_ai_usages
#
#  id              :bigint           not null, primary key
#  cost_micros     :bigint           default(0), not null
#  follow_up_count :integer          default(0), not null
#  handoff_count   :integer          default(0), not null
#  input_tokens    :bigint           default(0), not null
#  output_tokens   :bigint           default(0), not null
#  period          :string           not null
#  wait_count      :integer          default(0), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#
# Indexes
#
#  index_jivo_ai_usages_on_account_id_and_period  (account_id,period) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JivoAiUsage < ApplicationRecord
  belongs_to :account

  # AI idle follow-up action → the column that tracks how often it occurred.
  ACTION_COLUMNS = { 'follow_up' => 'follow_up_count', 'handoff' => 'handoff_count', 'wait' => 'wait_count' }.freeze

  # Atomically record one AI follow-up decision (its token usage and cost) against the
  # account's current-month row. Only AI-mode calls reach here, so each call = one billable
  # AI request. Cost is computed here, at the call's own model, and accumulated — so the
  # monthly total stays correct even when an account's assistants use different models.
  def self.record_action(account, action, model:, input_tokens: 0, output_tokens: 0)
    column = ACTION_COLUMNS[action.to_s]
    return unless column

    now = Time.current
    cost_micros = (Jivo::ModelPricing.cost(model: model, input_tokens: input_tokens.to_i, output_tokens: output_tokens.to_i) * 1_000_000).round
    row = { account_id: account.id, period: current_period, input_tokens: input_tokens.to_i, output_tokens: output_tokens.to_i,
            cost_micros: cost_micros, created_at: now, updated_at: now }.merge(column => 1)
    # Single atomic upsert: insert the month row or increment it in place, so concurrent
    # runs can't race the unique (account_id, period) index or clobber each other's counts.
    # rubocop:disable Rails/SkipsModelValidations
    upsert_all(
      [row],
      unique_by: %i[account_id period],
      on_duplicate: Arel.sql(
        "#{column} = jivo_ai_usages.#{column} + EXCLUDED.#{column}, " \
        'input_tokens = jivo_ai_usages.input_tokens + EXCLUDED.input_tokens, ' \
        'output_tokens = jivo_ai_usages.output_tokens + EXCLUDED.output_tokens, ' \
        'cost_micros = jivo_ai_usages.cost_micros + EXCLUDED.cost_micros, ' \
        'updated_at = EXCLUDED.updated_at'
      )
    )
    # rubocop:enable Rails/SkipsModelValidations
  end

  def self.current_month_for(account)
    find_by(account_id: account.id, period: current_period)
  end

  def self.current_period
    Time.current.strftime('%Y-%m')
  end

  def total
    follow_up_count + handoff_count + wait_count
  end

  # Rough USD estimate, summed per call at each call's own model (see record_action).
  # The price map is approximate, so treat this as a ballpark, not an invoice.
  def estimated_cost
    cost_micros / 1_000_000.0
  end
end
