class JivoAssistantPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end

  def avatar?
    @account_user.administrator?
  end

  def remove_avatar?
    @account_user.administrator?
  end

  def rewrite?
    @account_user.administrator? || @account_user.agent?
  end

  def summarize?
    @account_user.administrator? || @account_user.agent?
  end

  def reply_suggestion?
    @account_user.administrator? || @account_user.agent?
  end

  def label_suggestion?
    @account_user.administrator? || @account_user.agent?
  end

  def follow_up?
    @account_user.administrator? || @account_user.agent?
  end

  def learn_from_conversation?
    @account_user.administrator?
  end
end
