# == Schema Information
#
# Table name: jivo_ai_usages
#
#  id              :bigint           not null, primary key
#  follow_up_count :integer          default(0), not null
#  handoff_count   :integer          default(0), not null
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

  # Atomically record one AI follow-up decision against the account's current-month row.
  # Only AI-mode calls reach here, so each call = one billable AI request.
  def self.record_action(account, action)
    column = ACTION_COLUMNS[action.to_s]
    return unless column

    usage = find_or_create_by(account_id: account.id, period: current_period)
    # Atomic SQL increment so concurrent runs can't clobber each other's counts.
    where(id: usage.id).update_all("#{column} = #{column} + 1, updated_at = now()") # rubocop:disable Rails/SkipsModelValidations
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
end
