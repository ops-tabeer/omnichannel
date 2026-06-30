# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JivoAiUsage do
  let(:account) { create(:account) }
  let(:model) { 'gpt-4.1-mini' }
  let(:period) { Time.current.strftime('%Y-%m') }

  describe '.record_action' do
    it 'increments the column for a known action (TC-60)' do
      described_class.record_action(account, 'follow_up', model: model, input_tokens: 1, output_tokens: 1)
      expect(described_class.current_month_for(account).follow_up_count).to eq(1)
    end

    it 'ignores a nil action (TC-61)' do
      described_class.record_action(account, nil, model: model)
      expect(described_class.where(account_id: account.id)).to be_empty
    end

    it 'ignores an unknown action (TC-61)' do
      described_class.record_action(account, 'bogus', model: model)
      expect(described_class.where(account_id: account.id)).to be_empty
    end

    it 'accumulates tokens across calls (TC-62)' do
      described_class.record_action(account, 'follow_up', model: model, input_tokens: 1000, output_tokens: 10)
      described_class.record_action(account, 'wait', model: model, input_tokens: 200, output_tokens: 0)
      usage = described_class.current_month_for(account)
      expect([usage.input_tokens, usage.output_tokens]).to eq([1200, 10])
    end

    it 'keeps exactly one row per account per period (TC-63)' do
      5.times { described_class.record_action(account, 'wait', model: model, input_tokens: 1, output_tokens: 0) }
      expect(described_class.where(account_id: account.id, period: period).count).to eq(1)
    end

    it 'sums correctly over many sequential calls without losing counts (TC-64)' do
      10.times { described_class.record_action(account, 'follow_up', model: model, input_tokens: 1, output_tokens: 0) }
      expect(described_class.current_month_for(account).follow_up_count).to eq(10)
    end

    it 'records under the current YYYY-MM period (TC-65)' do
      described_class.record_action(account, 'handoff', model: model)
      expect(described_class.current_month_for(account).period).to eq(period)
    end

    it 'records a full per-action breakdown (TC-70)' do
      described_class.record_action(account, 'follow_up', model: model)
      described_class.record_action(account, 'handoff', model: model)
      described_class.record_action(account, 'wait', model: model)
      usage = described_class.current_month_for(account)
      expect([usage.follow_up_count, usage.handoff_count, usage.wait_count, usage.total]).to eq([1, 1, 1, 3])
    end
  end

  describe 'cost' do
    it 'computes cost at the call’s own model (TC-66)' do
      # gpt-4.1: (1000*2.00 + 100*8.00) / 1e6 = 0.0028 USD = 2800 micros
      described_class.record_action(account, 'follow_up', model: 'gpt-4.1', input_tokens: 1000, output_tokens: 100)
      expect(described_class.current_month_for(account).cost_micros).to eq(2800)
    end

    it 'sums a mixed-model month at each call’s own model (TC-67)' do
      described_class.record_action(account, 'follow_up', model: 'gpt-4.1', input_tokens: 1000, output_tokens: 100)
      described_class.record_action(account, 'wait', model: 'gpt-4.1-mini', input_tokens: 1000, output_tokens: 100)
      # 0.0028 + (1000*0.40 + 100*1.60)/1e6 = 0.0028 + 0.00056 = 0.00336
      expect(described_class.current_month_for(account).estimated_cost).to be_within(1e-9).of(0.00336)
    end

    it 'estimated_cost reads the stored micros (TC-68)' do
      usage = described_class.create!(account: account, period: period, cost_micros: 1_500_000)
      expect(usage.estimated_cost).to eq(1.5)
    end
  end

  describe '#total' do
    it 'sums the three action counts (TC-69)' do
      usage = described_class.new(follow_up_count: 2, handoff_count: 1, wait_count: 0)
      expect(usage.total).to eq(3)
    end
  end
end
