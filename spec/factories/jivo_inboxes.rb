# frozen_string_literal: true

FactoryBot.define do
  factory :jivo_inbox do
    account

    after(:build) do |jivo_inbox|
      jivo_inbox.jivo_assistant ||= create(:jivo_assistant, account: jivo_inbox.account)
      jivo_inbox.inbox ||= create(
        :inbox,
        account: jivo_inbox.account,
        channel: create(:channel_widget, account: jivo_inbox.account)
      )
    end
  end
end
