# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Super Admin account JIVO usage', type: :request do
  let!(:super_admin) { create(:super_admin) }
  let!(:account) { create(:account) }
  let(:period) { Time.current.strftime('%Y-%m') }

  before { sign_in(super_admin, scope: :super_admin) }

  describe 'GET /super_admin/accounts/:id' do
    it 'renders the current-month usage breakdown, tokens and cost (TC-80)' do
      JivoAiUsage.create!(account: account, period: period, follow_up_count: 190, handoff_count: 80,
                          wait_count: 42, input_tokens: 540_000, output_tokens: 28_000, cost_micros: 264_000)
      get "/super_admin/accounts/#{account.id}"
      expect(response.body).to include('JIVO idle follow-up AI calls')
      expect(response.body).to include('312 total')
      expect(response.body).to include('540,000')
      expect(response.body).to include('$0.2640')
    end

    it 'shows the empty state when there is no usage (TC-81)' do
      get "/super_admin/accounts/#{account.id}"
      expect(response.body).to include('No AI follow-up calls this month.')
    end

    it 'renders cost without depending on a JivoAssistant model lookup (TC-82)' do
      # No JivoAssistant exists for this account; cost still renders from stored micros.
      JivoAiUsage.create!(account: account, period: period, follow_up_count: 1, cost_micros: 500_000)
      get "/super_admin/accounts/#{account.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include('$0.5000')
    end
  end
end
