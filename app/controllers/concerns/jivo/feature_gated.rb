module Jivo::FeatureGated
  extend ActiveSupport::Concern

  included do
    before_action :ensure_jivo_enabled
  end

  private

  def ensure_jivo_enabled
    current_account unless Current.account
    return if performed?
    return if Current.account&.jivo_enabled

    render json: { error: 'JIVO is not enabled for this account' }, status: :forbidden
  end
end
