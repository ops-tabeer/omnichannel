class Jivo::Tools::FaqLookupTool < Jivo::Tools::BasePublicTool
  description 'Search FAQ responses using semantic similarity to find relevant answers'
  param :query, type: 'string', desc: 'The question or topic to search for in the FAQ database'

  def perform(tool_context, query:)
    log_tool_usage('searching', { query: query })

    responses = JivoAssistantResponse.search(query, jivo_assistant: @assistant).to_a

    if responses.empty?
      log_tool_usage('no_results', { query: query })
      "No relevant FAQs found for: #{query}"
    else
      log_tool_usage('found_results', { query: query, count: responses.size })
      collect_citations(tool_context, responses)
      format_responses(responses)
    end
  end

  private

  def format_responses(responses)
    responses.map { |response| format_response(response) }.join
  end

  def format_response(response)
    formatted = "
        Question: #{response.question}
        Answer: #{response.answer}
        "
    if should_show_source?(response)
      formatted += "
          Source: #{response.documentable.external_link}
          "
    end

    formatted
  end

  def should_show_source?(response)
    return false if response.documentable.blank?
    return false unless response.documentable.try(:external_link)

    !response.documentable.external_link.start_with?('PDF:')
  end

  def collect_citations(tool_context, responses)
    citations = tool_context.state[:citations] ||= []
    responses.each do |response|
      entry = build_citation(response)
      next if entry.nil?

      citations << entry unless citations.any? { |c| c[:document_id] == entry[:document_id] && c[:question] == entry[:question] }
    end
  end

  def build_citation(response)
    doc = response.documentable
    return nil unless doc

    link = doc.external_link
    link = nil if link.is_a?(String) && link.start_with?('PDF:')
    { document_id: response.documentable_id, external_link: link, document_name: doc.try(:name).presence || link, question: response.question }
  end
end
