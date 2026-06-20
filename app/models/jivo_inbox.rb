# == Schema Information
#
# Table name: jivo_inboxes
#
#  id                :bigint           not null, primary key
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  inbox_id          :bigint           not null
#  jivo_assistant_id :bigint           not null
#
# Indexes
#
#  index_jivo_inboxes_on_account_id         (account_id)
#  index_jivo_inboxes_on_inbox_id           (inbox_id) UNIQUE
#  index_jivo_inboxes_on_jivo_assistant_id  (jivo_assistant_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#  fk_rails_...  (jivo_assistant_id => jivo_assistants.id)
#

class JivoInbox < ApplicationRecord
  belongs_to :jivo_assistant
  belongs_to :inbox
  belongs_to :account

  validates :inbox_id, uniqueness: true

  before_validation :ensure_account_id

  private

  def ensure_account_id
    self.account_id = inbox&.account_id
  end
end
