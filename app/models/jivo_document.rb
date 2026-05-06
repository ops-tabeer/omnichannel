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
  has_one_attached :file

  enum status: { in_progress: 0, available: 1 }

  validates :external_link, uniqueness: { scope: :jivo_assistant_id }, allow_nil: true
  validates :content, length: { maximum: 200_000 }
  validate :must_have_source

  before_validation :ensure_account_id
  after_create_commit :enqueue_ingest

  def pdf?
    file.attached? && file.content_type.to_s.include?('pdf')
  end

  def openai_file_id
    metadata&.dig('openai_file_id')
  end

  def store_openai_file_id(file_id)
    update!(metadata: (metadata || {}).merge('openai_file_id' => file_id))
  end

  private

  def ensure_account_id
    self.account_id ||= jivo_assistant&.account_id
  end

  def must_have_source
    return if external_link.present? || file.attached?

    errors.add(:base, 'Either an external link or an attached file is required')
  end

  def enqueue_ingest
    if pdf?
      Jivo::Documents::PdfIngestJob.perform_later(self)
    elsif external_link.present?
      Jivo::Documents::CrawlJob.perform_later(self)
    end
  end
end
