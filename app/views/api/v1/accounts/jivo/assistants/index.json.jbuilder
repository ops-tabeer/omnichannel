json.array! @assistants do |assistant|
  json.partial! 'assistant', resource: assistant
end
