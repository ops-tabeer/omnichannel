# frozen_string_literal: true

FactoryBot.define do
  factory :jivo_assistant do
    sequence(:name) { |n| "Jivo Assistant #{n}" }
    description { 'Test idle follow-up assistant' }
    account
    config { {} }
  end
end
