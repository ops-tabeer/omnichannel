# == Schema Information
#
# Table name: jivo_assistant_responses
#
#  id                :bigint           not null, primary key
#  question          :string           not null
#  answer            :text             not null
#  embedding         :vector(1536)
#  status            :integer          default(1), not null
#  documentable_id   :bigint
#  documentable_type :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  jivo_assistant_id :bigint           not null
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
