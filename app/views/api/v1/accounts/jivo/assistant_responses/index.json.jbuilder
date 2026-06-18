json.payload do
  json.array! @responses do |response|
    json.partial! 'assistant_response', resource: response
  end
end

json.meta do
  json.total_count @responses_count
  json.page @current_page
end
