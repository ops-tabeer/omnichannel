# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jivo::ModelPricing do
  describe '.price_for' do
    it 'returns the configured rate for a known model (TC-71)' do
      expect(described_class.price_for('gpt-4o')).to eq(input: 2.50, output: 10.00)
    end

    it 'falls back to the default (mini) rate for an unknown model (TC-72)' do
      expect(described_class.price_for('made-up-model')).to eq(described_class::DEFAULT_PRICE)
    end

    it 'falls back to the default rate for a nil model (TC-72)' do
      expect(described_class.price_for(nil)).to eq(described_class::DEFAULT_PRICE)
    end
  end

  describe '.cost' do
    it 'prices input tokens at the model rate (TC-73)' do
      expect(described_class.cost(model: 'gpt-4.1-mini', input_tokens: 1_000_000, output_tokens: 0)).to eq(0.40)
    end

    it 'sums input and output token cost' do
      # gpt-4.1: 1000 * 2.00/1e6 + 100 * 8.00/1e6 = 0.0028
      expect(described_class.cost(model: 'gpt-4.1', input_tokens: 1000, output_tokens: 100)).to be_within(1e-9).of(0.0028)
    end
  end
end
