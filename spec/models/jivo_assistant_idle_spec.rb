# frozen_string_literal: true

require 'rails_helper'

# Idle follow-up config helpers + system-managed cutoff on JivoAssistant.
RSpec.describe JivoAssistant do
  let(:account) { create(:account) }

  def build_assistant(config = {})
    create(:jivo_assistant, account: account, config: config)
  end

  describe 'config defaults (TC-01)' do
    let(:assistant) { build_assistant }

    it 'uses sane defaults when nothing is set' do
      expect(assistant.idle_timeout_minutes_value).to eq(60)
      expect(assistant.idle_reminder_limit_value).to eq(3)
      expect(assistant.on_limit_action_value).to eq('handoff')
      expect(assistant).not_to be_idle_use_ai_enabled
      expect(assistant).not_to be_idle_action_enabled
    end
  end

  describe 'numeric fallbacks' do
    it 'falls back to default timeout for non-positive values (TC-02)' do
      expect(build_assistant('idle_timeout_minutes' => 0).idle_timeout_minutes_value).to eq(60)
      expect(build_assistant('idle_timeout_minutes' => '').idle_timeout_minutes_value).to eq(60)
    end

    it 'falls back to default limit for non-positive values (TC-03)' do
      expect(build_assistant('idle_reminder_limit' => 0).idle_reminder_limit_value).to eq(3)
    end
  end

  describe 'on_limit_action validation (TC-04)' do
    it 'keeps a valid value' do
      expect(build_assistant('on_limit_action' => 'none').on_limit_action_value).to eq('none')
    end

    it 'falls back to handoff for an invalid value' do
      expect(build_assistant('on_limit_action' => 'resolve').on_limit_action_value).to eq('handoff')
    end
  end

  describe 'boolean coercion (TC-05)' do
    it 'casts truthy strings' do
      expect(build_assistant('feature_idle_action' => 'true').idle_action_enabled?).to be(true)
      expect(build_assistant('idle_use_ai' => '1').idle_use_ai_enabled?).to be(true)
    end

    it 'casts falsy strings' do
      expect(build_assistant('feature_idle_action' => 'false').idle_action_enabled?).to be(false)
    end
  end

  describe 'idle_message_text fallback (TC-10)' do
    it 'returns the default when blank' do
      expect(build_assistant('idle_message' => '').idle_message_text).to be_present
    end

    it 'returns the custom message verbatim' do
      expect(build_assistant('idle_message' => 'Still there?').idle_message_text).to eq('Still there?')
    end
  end

  describe 'cutoff (idle_action_enabled_at)' do
    it 'is not stamped while disabled (TC-06)' do
      assistant = build_assistant('feature_idle_action' => false)
      expect(assistant.idle_action_enabled_at_value).to be_nil
    end

    it 'stamps now on a false→true toggle (TC-06)' do
      assistant = build_assistant('feature_idle_action' => false)
      assistant.update!(config: assistant.config.merge('feature_idle_action' => true))
      expect(assistant.idle_action_enabled_at_value).to be_within(5.seconds).of(Time.current)
    end

    it 'is not restamped on an unrelated save while enabled (TC-07)' do
      assistant = build_assistant('feature_idle_action' => true)
      original = assistant.idle_action_enabled_at_value
      travel_to(1.hour.from_now) do
        assistant.update!(config: assistant.config.merge('system_prompt' => 'changed'))
      end
      expect(assistant.idle_action_enabled_at_value).to be_within(1.second).of(original)
    end

    it 'restarts the window on re-enable (TC-08)' do
      assistant = build_assistant('feature_idle_action' => true)
      first = assistant.idle_action_enabled_at_value
      assistant.update!(config: assistant.config.merge('feature_idle_action' => false))
      travel_to(1.hour.from_now) do
        assistant.update!(config: assistant.config.merge('feature_idle_action' => true))
      end
      expect(assistant.idle_action_enabled_at_value).to be > first
    end

    it 'is preserved when the form replaces the whole config (TC-09)' do
      assistant = build_assistant('feature_idle_action' => true)
      original = assistant.idle_action_enabled_at_value
      # Settings form posts the whole config without the system-managed key.
      assistant.update!(config: { 'feature_idle_action' => true, 'idle_timeout_minutes' => 30 })
      expect(assistant.idle_action_enabled_at_value).to be_within(1.second).of(original)
    end
  end
end
