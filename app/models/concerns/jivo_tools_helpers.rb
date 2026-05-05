module JivoToolsHelpers
  extend ActiveSupport::Concern

  TOOL_REFERENCE_REGEX = %r{\[[^\]]+\]\(tool://([^/)]+)\)}

  class_methods do
    def built_in_agent_tools
      @built_in_agent_tools ||= load_agent_tools
    end

    def resolve_tool_class(tool_id)
      "Jivo::Tools::#{tool_id.classify}Tool".safe_constantize
    end

    def built_in_tool_ids
      @built_in_tool_ids ||= built_in_agent_tools.map { |tool| tool[:id] }
    end

    private

    def load_agent_tools
      tools_config = YAML.load_file(Rails.root.join('config/agents/jivo_tools.yml'))

      tools_config.filter_map do |tool_config|
        tool_class = resolve_tool_class(tool_config['id'])

        if tool_class
          {
            id: tool_config['id'],
            title: tool_config['title'],
            description: tool_config['description'],
            icon: tool_config['icon']
          }
        else
          Rails.logger.warn "JIVO Tool class not found for ID: #{tool_config['id']}"
          nil
        end
      end
    end
  end

  def extract_tool_ids_from_text(text)
    return [] if text.blank?

    text.scan(TOOL_REFERENCE_REGEX).flatten.uniq
  end

  def resolve_tool_instance(tool_id, assistant)
    klass = self.class.resolve_tool_class(tool_id)
    return klass.new(assistant) if klass

    custom = assistant.account.jivo_custom_tools.enabled.find_by(slug: tool_id)
    custom&.tool(assistant)
  end
end
