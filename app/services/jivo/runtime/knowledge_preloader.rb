class Jivo::Runtime::KnowledgePreloader
  pattr_initialize [:assistant!, :conversation, :normalized_history]

  def apply!(state)
    faqs = fetch_faqs
    state[:preloaded_knowledge] = faqs.map { |faq| { question: faq.question, answer: faq.answer } }
    state[:citations] = citations_from(faqs)
  end

  private

  def fetch_faqs
    args = conversation ? { conversation: conversation } : { message_history: normalized_history.to_a }
    Jivo::Knowledge::FaqContextService.new(assistant: assistant, **args).fetch
  end

  def citations_from(faqs)
    faqs.filter_map do |faq|
      doc = faq.documentable
      next unless doc

      link = doc.external_link
      link = nil if link.is_a?(String) && link.start_with?('PDF:')
      { document_id: faq.documentable_id, external_link: link, document_name: doc.try(:name).presence || link, question: faq.question }
    end
  end
end
