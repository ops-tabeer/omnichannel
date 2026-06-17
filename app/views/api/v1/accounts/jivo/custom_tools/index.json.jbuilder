json.array! @custom_tools do |tool|
  json.partial! 'custom_tool', resource: tool
end
