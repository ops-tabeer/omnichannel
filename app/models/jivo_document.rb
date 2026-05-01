# == Schema Information
#
# Table name: jivo_documents
#
#  id                :bigint           not null, primary key
#  name              :string
#  external_link     :string           not null
#  content           :text
#  status            :integer          default(0), not null
#  metadata          :jsonb            default({})
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  jivo_assistant_id :bigint           not null
#

class JivoDocument < ApplicationRecord
  belongs_to :jivo_assistant
  belongs_to :account
  has_many :jivo_assistant_responses,
           as: :documentable,
           class_name: 'JivoAssistantResponse',
           dependent: :destroy_async

  enum status: { in_progress: 0, available: 1 }

  validates :external_link, presence: true
  validates :external_link, uniqueness: { scope: :jivo_assistant_id }

  before_validation :ensure_account_id
  after_create_commit :enqueue_crawl

  private

  def ensure_account_id
    self.account_id ||= jivo_assistant&.account_id
  end

  def enqueue_crawl
    Jivo::Documents::CrawlJob.perform_later(self)
  end
end
