class Jivo::Tools::RateLimiter
  include Redis::RedisKeys

  WINDOW_SECONDS = 60

  class RateLimitExceeded < StandardError; end

  pattr_initialize [:custom_tool!]

  def check!
    limit = custom_tool.rate_limit_per_minute
    return if limit.blank? || limit.to_i <= 0

    count = increment_counter
    return if count <= limit.to_i

    raise RateLimitExceeded,
          "Rate limit exceeded for tool #{custom_tool.slug}: #{count}/#{limit} calls in the last #{WINDOW_SECONDS}s"
  end

  private

  def increment_counter
    count = Redis::Alfred.incr(redis_key)
    Redis::Alfred.expire(redis_key, WINDOW_SECONDS) if count == 1
    count
  end

  def redis_key
    format(JIVO_TOOL_RATE_LIMIT_KEY, account_id: custom_tool.account_id, tool_slug: custom_tool.slug)
  end
end
