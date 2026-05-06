json.id resource.id
json.name resource.name
json.description resource.description
json.config resource.config
json.response_guidelines Array(resource.response_guidelines)
json.guardrails Array(resource.guardrails)
json.available_tools resource.available_agent_tools
json.avatar_url resource.avatar.attached? ? Rails.application.routes.url_helpers.url_for(resource.avatar) : nil
json.created_at resource.created_at.to_i
json.updated_at resource.updated_at.to_i
json.inboxes(resource.inboxes.pluck(:id, :name).map { |id, name| { id: id, name: name } })
