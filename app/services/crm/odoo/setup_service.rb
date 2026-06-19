class Crm::Odoo::SetupService
  def initialize(hook)
    @hook = hook
  end

  # Synchronous credential check used on hook create. Authenticates the bot user
  # and reads its display name, stashing the resolved uid + connected_user into
  # settings so they are persisted with the record. Raises ApiError on failure so
  # the caller can block the connect with a clear message.
  def validate_connection!
    client = build_client(@hook.settings['api_key'])
    uid = client.authenticate
    @hook.settings = @hook.settings.merge('uid' => uid, 'connected_user' => fetch_user_name(client, uid))
  end

  # Runs after create (async). Moves the api key from the plaintext settings into
  # the encrypted access_token column. Reuses the uid/connected_user resolved during
  # validation; re-authenticates only if they are missing.
  def setup
    resolve_and_persist
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @hook.account).capture_exception
    Rails.logger.error "Odoo setup failed for hook ##{@hook.id}: #{e.message}"
  end

  private

  def resolve_and_persist
    api_key = @hook.settings['api_key'].presence || @hook.access_token
    client = build_client(api_key)
    uid = @hook.settings['uid'].presence || client.authenticate
    connected_user = @hook.settings['connected_user'].presence || fetch_user_name(client, uid)
    persist_credentials(api_key, uid, connected_user)
  end

  def build_client(api_key)
    Crm::Odoo::Api::Client.new(
      url: @hook.settings['url'],
      db: @hook.settings['db'],
      login: @hook.settings['login'],
      api_key: api_key
    )
  end

  def fetch_user_name(client, uid)
    record = client.execute_kw('res.users', 'read', [[uid], %w[name]]).to_a.first
    record&.dig('name')
  end

  def persist_credentials(api_key, uid, connected_user)
    @hook.settings = @hook.settings.except('api_key').merge('uid' => uid, 'connected_user' => connected_user)
    @hook.access_token = api_key
    @hook.save!
  end
end
