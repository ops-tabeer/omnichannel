require 'net/http'
require 'nokogiri'
require 'uri'

class Jivo::Tools::SimplePageCrawlService
  REQUEST_TIMEOUT = 20
  MAX_CONTENT_LENGTH = 100_000
  USER_AGENT = 'Mozilla/5.0 (compatible; JIVO-AI/1.0)'.freeze

  pattr_initialize [:url!]

  def perform
    html = fetch_page
    return blank_result if html.blank?

    parse(html)
  rescue StandardError => e
    Rails.logger.warn "[JIVO] Page crawl failed for #{url}: #{e.message}"
    blank_result
  end

  private

  def fetch_page
    uri = URI.parse(url)
    raise 'Invalid URL scheme' unless %w[http https].include?(uri.scheme)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 10
    http.read_timeout = REQUEST_TIMEOUT

    request = Net::HTTP::Get.new(uri.request_uri)
    request['User-Agent'] = USER_AGENT
    request['Accept'] = 'text/html'

    response = http.request(request)
    return nil unless response.is_a?(Net::HTTPSuccess)

    response.body
  end

  def parse(html)
    doc = Nokogiri::HTML(html)

    doc.css('script, style, noscript, iframe, svg').remove

    title = doc.at_css('title')&.text&.strip
    description = doc.at_css('meta[name="description"]')&.[]('content')&.strip
    body_text = (doc.at_css('main') || doc.at_css('article') || doc.at_css('body'))
                .text
                .gsub(/\s+/, ' ')
                .strip[0, MAX_CONTENT_LENGTH]

    {
      title: title,
      description: description,
      content: body_text
    }
  end

  def blank_result
    { title: nil, description: nil, content: nil }
  end
end
