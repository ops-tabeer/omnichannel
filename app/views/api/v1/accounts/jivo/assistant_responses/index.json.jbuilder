json.array! @responses do |response|
  json.partial! 'assistant_response', resource: response
end
