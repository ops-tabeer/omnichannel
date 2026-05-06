json.id resource.id
json.name resource.name
json.external_link resource.external_link
json.status resource.status
json.metadata resource.metadata
json.file_attached resource.file.attached?
json.file_name resource.file.attached? ? resource.file.filename.to_s : nil
json.file_content_type resource.file.attached? ? resource.file.content_type : nil
json.created_at resource.created_at.to_i
json.updated_at resource.updated_at.to_i
json.responses_count resource.jivo_assistant_responses.count
