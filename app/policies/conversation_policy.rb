class ConversationPolicy < ApplicationPolicy
  def index?
    true
  end

  def destroy?
    administrator?
  end

  def show?
    administrator? || agent_bot? || agent_can_view_conversation?
  end

  # Only the current assignee or an admin may take a conversation. Enforced server-side
  # so a stale UI (e.g. after an idle reassignment) can't take a conversation it no
  # longer owns and create an Odoo lead for the wrong agent.
  def take?
    administrator? || assigned_to_user?
  end

  # Manual assign/reassign (self or to another agent) is restricted to admins and
  # explicitly allow-listed agents, so sales agents can't grab conversations the AI is
  # handling. Agent bots (automation) are allowed. Other automated flows (round-robin,
  # auto-assignment, handoff) run in system context and never reach this policy.
  def assign?
    assignment_privileged?
  end

  # Moving a conversation (back) to open is restricted to the same allow-list, so a
  # restricted agent can't reopen/interrupt an AI- or manager-controlled conversation.
  # Resolving, snoozing and marking pending stay open to any agent.
  def reopen?
    assignment_privileged?
  end

  private

  # Shared allow-list for assignment and reopen: admins, agent bots (automation),
  # and agents explicitly flagged as allowed.
  def assignment_privileged?
    administrator? || agent_bot? || account_user&.assignment_allowed?
  end

  def agent_can_view_conversation?
    inbox_access? || team_access?
  end

  def administrator?
    account_user&.administrator?
  end

  def agent_bot?
    user.is_a?(AgentBot)
  end

  def inbox_access?
    user.inboxes.where(account_id: account&.id).exists?(id: record.inbox_id)
  end

  def team_access?
    return false if record.team_id.blank?

    user.teams.where(account_id: account&.id).exists?(id: record.team_id)
  end

  def assigned_to_user?
    record.assignee_id == user.id
  end

  def participant?
    record.conversation_participants.exists?(user_id: user.id)
  end
end

ConversationPolicy.prepend_mod_with('ConversationPolicy')
