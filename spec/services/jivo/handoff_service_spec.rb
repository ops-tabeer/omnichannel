# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jivo::HandoffService do
  let(:account) { create(:account) }
  let(:assistant) { create(:jivo_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account, status: 'pending') }

  before do
    # Don't let the out-of-office template create real messages unless we're asserting on it.
    allow(MessageTemplates::Template::OutOfOffice).to receive(:perform_if_applicable)
  end

  def private_notes(conversation) = conversation.reload.messages.where(private: true)

  it 'flips a pending conversation to open (TC-55)' do
    described_class.new(conversation: conversation, assistant: assistant, reason: 'note').perform
    expect(conversation.reload.status).to eq('open')
  end

  it 'sets the ai_handoff flag so inbox reassignment can take over (TC-56)' do
    described_class.new(conversation: conversation, assistant: assistant, reason: 'note').perform
    expect(conversation.reload.custom_attributes['ai_handoff']).to be(true)
  end

  it 'posts the reason as a private note (TC-57)' do
    described_class.new(conversation: conversation, assistant: assistant, reason: 'Handed off by JIVO').perform
    expect(private_notes(conversation).last.content).to eq('Handed off by JIVO')
  end

  it 'posts no note when reason is blank (TC-57)' do
    expect do
      described_class.new(conversation: conversation, assistant: assistant, reason: '').perform
    end.not_to(change { private_notes(conversation).count })
  end

  it 'sends the out-of-office message when there is no campaign (TC-58)' do
    described_class.new(conversation: conversation, assistant: assistant, reason: 'x').perform
    expect(MessageTemplates::Template::OutOfOffice).to have_received(:perform_if_applicable).with(conversation)
  end

  it 'skips the out-of-office message when a campaign is present (TC-58)' do
    allow(conversation).to receive(:campaign).and_return(create(:campaign, account: account, inbox: conversation.inbox))
    described_class.new(conversation: conversation, assistant: assistant, reason: 'x').perform
    expect(MessageTemplates::Template::OutOfOffice).not_to have_received(:perform_if_applicable)
  end

  it 'constructs with reason defaulting to nil (TC-59 attr_extras regression)' do
    expect { described_class.new(conversation: conversation, assistant: assistant) }.not_to raise_error
  end
end
