class Jivo::Documents::PaginatedFaqGeneratorService
  DEFAULT_PAGES_PER_CHUNK = 10
  MAX_ITERATIONS = 20

  attr_reader :total_pages_processed, :iterations_completed

  def initialize(document:, pages_per_chunk: DEFAULT_PAGES_PER_CHUNK, max_pages: nil)
    @document = document
    @assistant = document.jivo_assistant
    @pages_per_chunk = pages_per_chunk
    @max_pages = max_pages
    @total_pages_processed = 0
    @iterations_completed = 0
  end

  def generate
    raise 'OpenAI file id missing for PDF document' if document.openai_file_id.blank?

    generate_paginated_faqs
  end

  private

  attr_reader :document, :assistant, :pages_per_chunk, :max_pages

  def generate_paginated_faqs
    all_faqs = []
    current_page = 1

    loop do
      end_page = calculate_end_page(current_page)
      chunk_result = process_page_chunk(current_page, end_page)
      all_faqs.concat(chunk_result[:faqs])
      @total_pages_processed = end_page
      @iterations_completed += 1

      break unless continue_processing?(chunk_result)

      current_page = end_page + 1
    end

    dedupe(all_faqs)
  end

  def calculate_end_page(current_page)
    end_page = current_page + pages_per_chunk - 1
    max_pages && end_page > max_pages ? max_pages : end_page
  end

  def continue_processing?(chunk_result)
    return false if iterations_completed >= MAX_ITERATIONS
    return false if max_pages && total_pages_processed >= max_pages
    return false if chunk_result[:faqs].empty?

    chunk_result[:has_content] != false
  end

  def process_page_chunk(start_page, end_page)
    response = client.chat(parameters: chunk_parameters(start_page, end_page))
    result = parse_response(response)
    { faqs: result['faqs'] || [], has_content: result['has_content'] != false }
  rescue OpenAI::Error => e
    Rails.logger.error "[JIVO] PDF page processing failed for pages #{start_page}-#{end_page}: #{e.message}"
    { faqs: [], has_content: false }
  end

  def chunk_parameters(start_page, end_page)
    {
      model: assistant.model,
      response_format: { type: 'json_object' },
      messages: [
        {
          role: 'user',
          content: [
            { type: 'file', file: { file_id: document.openai_file_id } },
            { type: 'text', text: page_chunk_prompt(start_page, end_page) }
          ]
        }
      ]
    }
  end

  def page_chunk_prompt(start_page, end_page)
    <<~PROMPT
      You are an expert travel documentation specialist creating comprehensive FAQs from a specific section of a PDF.

      Process the content starting from approximately page #{start_page} and continuing through page #{end_page}.

      Critical requirements:
      - Extract ALL customer-facing information from this section.
      - Do not only extract explicit Q/A pairs.
      - Convert standalone Product, Cost, Details, Requirements, Inclusions, Notes, restrictions, policies, and warnings into FAQs.
      - Preserve every price, nationality restriction, eligibility rule, refund rule, requirement, inclusion, exclusion, and mandatory note.
      - If a Product/Cost block has no question, create a natural customer question for it.
      - If a note changes who a price applies to, include that note in the answer.
      - Do not invent information not present in the PDF.
      - Do not mention page numbers in questions or answers.
      - Generate the FAQs only in #{document.account.locale_english_name}.

      Return valid JSON only:
      {
        "faqs": [
          { "question": "Specific customer question", "answer": "Complete answer with all details from the PDF section" }
        ],
        "has_content": true
      }

      Set "has_content" to false only if this section has no meaningful content or the requested pages do not exist.
    PROMPT
  end

  def parse_response(response)
    content = response.dig('choices', 0, 'message', 'content')
    return { 'faqs' => [], 'has_content' => false } if content.blank?

    JSON.parse(content.strip)
  rescue JSON::ParserError => e
    Rails.logger.error "[JIVO] PDF chunk response parse failed: #{e.message}"
    { 'faqs' => [], 'has_content' => false }
  end

  def dedupe(faqs)
    faqs.uniq { |faq| faq['question'].to_s.downcase.strip }
  end

  def client
    @client ||= OpenAI::Client.new(
      access_token: assistant.effective_openai_api_key,
      log_errors: Rails.env.development?
    )
  end
end
