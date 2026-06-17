require 'pdf-reader'

class Jivo::Documents::PdfTextExtractor
  pattr_initialize [:document!]

  def perform
    raise 'No file attached' unless document.file.attached?

    document.file.blob.open do |file|
      reader = PDF::Reader.new(file)
      pages_text = reader.pages.map { |page| page.text.to_s.strip }
      pages_text.reject(&:blank?).join("\n\n")
    end
  end
end
