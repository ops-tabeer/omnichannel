json.array! @scenarios do |scenario|
  json.partial! 'scenario', resource: scenario
end
