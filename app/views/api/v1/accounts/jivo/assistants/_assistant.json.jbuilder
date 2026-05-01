json.id resource.id
json.name resource.name
json.description resource.description
json.config resource.config
json.created_at resource.created_at.to_i
json.updated_at resource.updated_at.to_i
json.inboxes resource.inboxes.pluck(:id, :name).map { |id, name| { id: id, name: name } }
