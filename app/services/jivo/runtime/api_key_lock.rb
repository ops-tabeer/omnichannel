module Jivo::Runtime::ApiKeyLock
  MUTEX = Mutex.new

  module_function

  def with_assistant_key(assistant)
    MUTEX.synchronize do
      previous = snapshot_config
      begin
        apply(openai_api_key: assistant.openai_api_key, default_model: assistant.model)
        yield
      ensure
        apply(**previous)
      end
    end
  end

  def snapshot_config
    config = Agents.configuration
    { openai_api_key: config.openai_api_key, default_model: config.default_model }
  end

  def apply(openai_api_key:, default_model:)
    Agents.configure do |config|
      config.openai_api_key = openai_api_key
      config.default_model = default_model
    end
  end
end
