# frozen_string_literal: true

require 'rails_helper'

# Baton-pass guard: the inbox idle-reassignment service must NOT touch pending conversations
# (the JIVO idle follow-up phase). The two operate on disjoint statuses, so there is no
# double-acting. See JIVO_FOLLOWUP_PLAN.md §6.
# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe AutoAssignment::IdleReassignmentService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }

  before do
    allow(inbox).to receive_messages(auto_reassignment_enabled?: true, auto_reassignment_threshold: 60)
  end

  it 'ignores a pending conversation (TC-78)' do
    conversation = create(:conversation, account: account, inbox: inbox, status: 'pending')
    conversation.update_columns(last_activity_at: 2.hours.ago) # rubocop:disable Rails/SkipsModelValidations

    expect { described_class.new(inbox: inbox).perform }.not_to(change { conversation.reload.assignee_id })
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
