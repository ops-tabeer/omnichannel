class Jivo::Tools::FaqLookupTool < Jivo::Tools::BasePublicTool
  description 'Search FAQ responses using semantic similarity to find relevant answers'
  param :query, type: 'string', desc: 'The question or topic to search for in the FAQ database'

  def perform(_tool_context, query:)
    log_tool_usage('searching', { query: query })

    responses = JivoAssistantResponse.search(query, jivo_assistant: @assistant).to_a

    if responses.empty?
      log_tool_usage('no_results', { query: query })
      "No relevant FAQs found for: #{query}"
    else
      log_tool_usage('found_results', { query: query, count: responses.size })
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
end
