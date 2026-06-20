# == Schema Information
#
# Table name: jivo_assistant_responses
#
#  id                :bigint           not null, primary key
#  answer            :text             not null
#  documentable_type :string
#  embedding         :vector(1536)
#  question          :string           not null
#  status            :integer          default("approved"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  documentable_id   :bigint
#  jivo_assistant_id :bigint           not null
#
# Indexes
#
#  idx_jivo_resp_embedding                              (embedding) USING ivfflat
#  idx_jivo_resp_on_documentable                        (documentable_id,documentable_type)
#  index_jivo_assistant_responses_on_account_id         (account_id)
#  index_jivo_assistant_responses_on_jivo_assistant_id  (jivo_assistant_id)
#  index_jivo_assistant_responses_on_status             (status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (jivo_assistant_id => jivo_assistants.id)
#

class JivoAssistantResponse < ApplicationRecord
  belongs_to :jivo_assistant
  belongs_to :account
  belongs_to :documentable, polymorphic: true, optional: true

  has_neighbors :embedding, normalize: true

  validates :question, presence: true
  validates :answer, presence: true

  before_validation :ensure_account_id
  after_commit :update_response_embedding

  scope :ordered, -> { order(created_at: :desc) }
  scope :approved_only, -> { approved }

  enum status: { pending: 0, approved: 1 }

  def self.search(query, jivo_assistant:)
    translated_query = Jivo::Llm::TranslateQueryService
                       .new(assistant: jivo_assistant)
                       .translate(query, target_language: jivo_assistant.account.locale_english_name)
    embedding = Jivo::Llm::EmbeddingService.new(assistant: jivo_assistant).get_embedding(translated_query)
    return none if embedding.blank?

    where(jivo_assistant_id: jivo_assistant.id)
      .approved
      .nearest_neighbors(:embedding, embedding, distance: 'cosine')
      .limit(5)
  end

  private

  def ensure_account_id
    self.account_id ||= jivo_assistant&.account_id
  end

  def update_response_embedding
    return unless saved_change_to_question? || saved_change_to_answer? || embedding.nil?

    Jivo::Llm::UpdateEmbeddingJob.perform_later(self, "#{question}: #{answer}")
  end
end
