module JivoAgentable
  extend ActiveSupport::Concern

  def agent
    Agents::Agent.new(
      name: agent_name,
      instructions: ->(context) { agent_instructions(context) },
      tools: agent_tool_instances,
      model: agent_model,
      temperature: temperature_value,
      response_schema: Jivo::ResponseSchema
    )
  end

  def agent_instructions(_context = nil)
    raise NotImplementedError, "#{self.class} must implement agent_instructions"
  end

  private

  def agent_name
    raise NotImplementedError, "#{self.class} must implement agent_name"
  end

  def agent_tool_instances
    raise NotImplementedError, "#{self.class} must implement agent_tool_instances"
  end

  def agent_model
    self.class.respond_to?(:default_model) ? self.class.default_model : 'gpt-4.1-mini'
  end
end
