# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jivo::Tasks::IdleFollowUpService do
  let(:account) { create(:account) }
  let(:assistant) { create(:jivo_assistant, account: account, config: { 'idle_prompt' => 'Ask for the phone number.' }) }
  let(:conversation) { create(:conversation, account: account) }
  let(:service) { described_class.new(assistant: assistant, conversation: conversation) }

  def response_with(content, prompt_tokens: 12, completion_tokens: 8)
    {
      'choices' => [{ 'message' => { 'content' => content } }],
      'usage' => { 'prompt_tokens' => prompt_tokens, 'completion_tokens' => completion_tokens }
    }
  end

  describe '#build_result' do
    it 'parses follow_up and merges token usage (TC-76)' do
      result = service.send(:build_result, response_with('{"action":"follow_up","message":"Hi there"}'))
      expect(result).to include(success: true, action: 'follow_up', message: 'Hi there', input_tokens: 12, output_tokens: 8)
    end

    it 'parses handoff with token usage (TC-76)' do
      result = service.send(:build_result, response_with('{"action":"handoff","message":""}'))
      expect(result).to include(action: 'handoff', input_tokens: 12, output_tokens: 8)
    end

    it 'parses wait with token usage (TC-76)' do
      result = service.send(:build_result, response_with('{"action":"wait","message":""}'))
      expect(result).to include(action: 'wait', input_tokens: 12, output_tokens: 8)
    end

    it 'degrades a non-JSON body to wait, still carrying tokens (TC-48)' do
      result = service.send(:build_result, response_with('not json at all'))
      expect(result).to include(action: 'wait', input_tokens: 12, output_tokens: 8)
    end

    it 'degrades an unknown action to wait (TC-49)' do
      result = service.send(:build_result, response_with('{"action":"banana","message":"x"}'))
      expect(result).to include(action: 'wait')
    end
  end

  describe '#system_prompt (TC-34)' do
    it 'includes the assistant idle_prompt and the customer-language rule' do
      prompt = service.send(:system_prompt)
      expect(prompt).to include('Ask for the phone number.')
      expect(prompt).to match(/same language as the customer/i)
    end
  end
end
