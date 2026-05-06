module Jivo::FirecrawlHelper
  def generate_jivo_firecrawl_token(assistant_id, account_id)
    api_key = InstallationConfig.find_by(name: 'JIVO_FIRECRAWL_API_KEY')&.value
    return nil if api_key.blank?

    Digest::SHA256.hexdigest("#{api_key[-4..]}#{assistant_id}#{account_id}")
  end
end
