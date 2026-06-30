# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jivo::Tasks::BaseTaskService do
  let(:account) { create(:account) }
  let(:assistant) { create(:jivo_assistant, account: account) }
  let(:service) { described_class.new(assistant: assistant) }

  describe '#token_usage' do
    it 'extracts prompt and completion tokens (TC-74)' do
      response = { 'usage' => { 'prompt_tokens' => 123, 'completion_tokens' => 45 } }
      expect(service.send(:token_usage, response)).to eq(input_tokens: 123, output_tokens: 45)
    end

    it 'returns zeros when the usage block is missing (TC-75)' do
      expect(service.send(:token_usage, {})).to eq(input_tokens: 0, output_tokens: 0)
    end
  end
end
