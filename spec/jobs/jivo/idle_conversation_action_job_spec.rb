# frozen_string_literal: true

require 'rails_helper'

# update_columns is used to set last_activity_at/created_at/status without firing the
# activity callbacks; any_instance is used to stub the job's own private helpers.
# rubocop:disable Rails/SkipsModelValidations, RSpec/AnyInstance
RSpec.describe Jivo::IdleConversationActionJob do
  let(:account) { create(:account) }
  let(:jivo_inbox) { create(:jivo_inbox, account: account) }
  let(:inbox) { jivo_inbox.inbox }
  let(:assistant) { jivo_inbox.jivo_assistant }

  # HandoffService is exercised in its own spec; here we stub it so the job's branching is
  # isolated and nothing can be delivered to a channel.
  let(:handoff_service) { instance_double(Jivo::HandoffService, perform: true) }

  before do
    allow(Jivo::HandoffService).to receive(:new).and_return(handoff_service)
    enable_idle!(assistant)
  end

  # Two-step enable: flipping the feature stamps the cutoff "now"; then we push the cutoff
  # back so freshly-created test conversations qualify.
  def enable_idle!(asst, extra = {})
    asst.update!(config: asst.config.merge(
      'feature_idle_action' => true, 'idle_timeout_minutes' => 60,
      'idle_reminder_limit' => 3, 'on_limit_action' => 'handoff'
    ).merge(extra))
    asst.update!(config: asst.config.merge('idle_action_enabled_at' => 2.hours.ago.iso8601))
  end

  def pending_idle(target_inbox = inbox, attempt: 0, last_activity: 2.hours.ago, checked_at: nil, created_at: 1.hour.ago)
    conversation = create(:conversation, account: account, inbox: target_inbox, status: 'pending')
    attrs = { 'jivo_idle_reminder_count' => attempt }
    attrs['jivo_idle_checked_at'] = checked_at.iso8601 if checked_at
    conversation.update_columns(last_activity_at: last_activity, created_at: created_at, custom_attributes: attrs)
    conversation
  end

  def stub_ai(action:, message: '', input_tokens: 100, output_tokens: 10)
    result = { success: true, action: action, message: message, input_tokens: input_tokens, output_tokens: output_tokens }
    allow(Jivo::Tasks::IdleFollowUpService).to receive(:new).and_return(instance_double(Jivo::Tasks::IdleFollowUpService, perform: result))
  end

  def run! = described_class.new.perform

  def outgoing_count(conversation) = conversation.reload.messages.where(message_type: :outgoing, private: false).count
  def attempts(conversation) = conversation.reload.custom_attributes['jivo_idle_reminder_count'].to_i

  describe 'eligibility & scoping' do
    it 'sends a follow-up to a pending idle conversation (TC-13)' do
      conversation = pending_idle
      expect { run! }.to change { outgoing_count(conversation) }.by(1)
    end

    it 'skips a conversation that is not yet idle (TC-14)' do
      conversation = pending_idle(last_activity: 59.minutes.ago)
      expect { run! }.not_to(change { outgoing_count(conversation) })
    end

    it 'skips non-pending conversations (TC-15)' do
      conversation = pending_idle
      conversation.update_columns(status: Conversation.statuses['open'])
      expect { run! }.not_to(change { outgoing_count(conversation) })
    end

    it 'never acts on the pre-cutoff backlog (TC-16)' do
      conversation = pending_idle(created_at: 3.hours.ago) # before the 2h-ago cutoff
      expect { run! }.not_to(change { outgoing_count(conversation) })
    end

    it 'skips inboxes whose assistant has the feature disabled (TC-12)' do
      other = create(:jivo_inbox, account: account)
      conversation = pending_idle(other.inbox)
      expect { run! }.not_to(change { outgoing_count(conversation) })
    end

    it 'never visits non-JIVO inboxes (TC-11)' do
      plain = create(:inbox, account: account, channel: create(:channel_widget, account: account))
      conversation = pending_idle(plain)
      expect { run! }.not_to(change { outgoing_count(conversation) })
    end

    it 'continues after a per-conversation failure (TC-22)' do
      bad = pending_idle
      good = pending_idle
      # Raise inside apply_idle_action (post_follow_up) so the job's own rescue is exercised.
      allow_any_instance_of(described_class).to receive(:create_outgoing_message).and_call_original
      allow_any_instance_of(described_class).to receive(:create_outgoing_message).with(bad, anything, anything).and_raise('boom')
      allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: true))
      expect { run! }.to change { outgoing_count(good) }.by(1)
    end
  end

  describe 'static mode (AI off)' do
    it 'posts the static idle_message and counts one attempt (TC-24)' do
      enable_idle!(assistant, 'idle_use_ai' => false, 'idle_message' => 'Still there?')
      conversation = pending_idle
      run!
      expect(conversation.reload.messages.last.content).to eq('Still there?')
      expect(attempts(conversation)).to eq(1)
    end

    it 'records zero AI usage in static mode (TC-27 cost-leak)' do
      enable_idle!(assistant, 'idle_use_ai' => false)
      pending_idle
      expect { run! }.not_to change(JivoAiUsage, :count).from(0)
    end
  end

  describe 'AI mode actions' do
    before { enable_idle!(assistant, 'idle_use_ai' => true, 'idle_prompt' => 'Ask for phone.') }

    it 'posts the AI message, counts an attempt and records usage (TC-29)' do
      stub_ai(action: 'follow_up', message: 'Hi!')
      conversation = pending_idle
      run!
      expect(conversation.reload.messages.last.content).to eq('Hi!')
      expect(attempts(conversation)).to eq(1)
      expect(JivoAiUsage.current_month_for(account).follow_up_count).to eq(1)
    end

    it 'falls back to idle_message when follow_up message is blank (TC-30)' do
      enable_idle!(assistant, 'idle_use_ai' => true, 'idle_message' => 'Default check-in')
      stub_ai(action: 'follow_up', message: '')
      conversation = pending_idle
      run!
      expect(conversation.reload.messages.last.content).to eq('Default check-in')
    end

    it 'hands off immediately on the handoff action without a message (TC-31)' do
      stub_ai(action: 'handoff')
      conversation = pending_idle
      run!
      expect(outgoing_count(conversation)).to eq(0)
      expect(attempts(conversation)).to eq(0)
      expect(Jivo::HandoffService).to have_received(:new).with(hash_including(conversation: conversation))
      expect(JivoAiUsage.current_month_for(account).handoff_count).to eq(1)
    end

    it 'counts a wait without sending a message (TC-32)' do
      stub_ai(action: 'wait')
      conversation = pending_idle
      run!
      expect(outgoing_count(conversation)).to eq(0)
      expect(attempts(conversation)).to eq(1)
      expect(JivoAiUsage.current_month_for(account).wait_count).to eq(1)
    end

    it 'escalates in the same run when a wait reaches the limit (TC-33)' do
      stub_ai(action: 'wait')
      conversation = pending_idle(attempt: 2) # limit 3 → this wait makes it 3
      run!
      expect(attempts(conversation)).to eq(3)
      expect(Jivo::HandoffService).to have_received(:new).with(hash_including(conversation: conversation))
    end
  end

  describe 'AI re-check spacing (marker)' do
    before { enable_idle!(assistant, 'idle_use_ai' => true, 'idle_prompt' => 'x') }

    it 'stamps the checked-at marker on an AI run (TC-37)' do
      stub_ai(action: 'wait')
      conversation = pending_idle
      run!
      expect(conversation.reload.custom_attributes['jivo_idle_checked_at']).to be_present
    end

    it 'skips the AI call when checked within the idle window (TC-38)' do
      allow(Jivo::Tasks::IdleFollowUpService).to receive(:new)
      conversation = pending_idle(checked_at: 30.minutes.ago)
      run!
      expect(Jivo::Tasks::IdleFollowUpService).not_to have_received(:new)
      expect(attempts(conversation)).to eq(0)
    end

    it 'runs the AI when the last check is older than the idle window (TC-39)' do
      stub_ai(action: 'wait')
      pending_idle(checked_at: 61.minutes.ago)
      run!
      expect(Jivo::Tasks::IdleFollowUpService).to have_received(:new)
    end

    it 'calls the AI only once across repeated runs within the window (TC-41 cost-leak)' do
      stub_ai(action: 'wait')
      pending_idle
      3.times { run! }
      expect(Jivo::Tasks::IdleFollowUpService).to have_received(:new).once
      expect(JivoAiUsage.current_month_for(account).wait_count).to eq(1)
    end
  end

  describe 'AI error handling' do
    before { enable_idle!(assistant, 'idle_use_ai' => true, 'idle_prompt' => 'x') }

    it 'takes no action on a hard error: no attempt, no handoff, no usage (TC-44/45/46)' do
      allow(Jivo::Tasks::IdleFollowUpService).to receive(:new)
        .and_return(instance_double(Jivo::Tasks::IdleFollowUpService, perform: { success: false, error: 'boom' }))
      conversation = pending_idle
      run!
      expect(attempts(conversation)).to eq(0)
      expect(outgoing_count(conversation)).to eq(0)
      expect(Jivo::HandoffService).not_to have_received(:new)
      expect(JivoAiUsage.count).to eq(0)
    end
  end

  describe 'attempt limit & escalation' do
    it 'escalates at the limit without calling the AI (TC-50)' do
      enable_idle!(assistant, 'idle_use_ai' => true, 'idle_prompt' => 'x')
      allow(Jivo::Tasks::IdleFollowUpService).to receive(:new)
      conversation = pending_idle(attempt: 3) # already at limit
      run!
      expect(Jivo::Tasks::IdleFollowUpService).not_to have_received(:new)
      expect(Jivo::HandoffService).to have_received(:new)
        .with(hash_including(conversation: conversation, reason: I18n.t('conversations.jivo.idle_handoff_reason')))
    end

    it 'leaves the conversation pending when on_limit_action is none (TC-52)' do
      enable_idle!(assistant, 'on_limit_action' => 'none')
      pending_idle(attempt: 3)
      run!
      expect(Jivo::HandoffService).not_to have_received(:new)
    end

    it 'uses the AI handoff reason for an AI-decided handoff (TC-54)' do
      enable_idle!(assistant, 'idle_use_ai' => true, 'idle_prompt' => 'x')
      stub_ai(action: 'handoff')
      conversation = pending_idle
      run!
      expect(Jivo::HandoffService).to have_received(:new)
        .with(hash_including(conversation: conversation, reason: I18n.t('conversations.jivo.idle_ai_handoff_reason')))
    end
  end
end
# rubocop:enable Rails/SkipsModelValidations, RSpec/AnyInstance
