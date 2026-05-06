json.array! @responses do |response|
  json.partial! 'api/v1/accounts/jivo/assistant_responses/assistant_response', resource: response
end
