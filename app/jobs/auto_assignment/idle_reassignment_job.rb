class AutoAssignment::IdleReassignmentJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Inbox.where(auto_reassignment_enabled: true).find_each do |inbox|
      AutoAssignment::IdleReassignmentService.new(inbox: inbox).perform
    rescue StandardError => e
      Rails.logger.error "IdleReassignment failed for inbox #{inbox.id}: #{e.message}"
    end
  end
end
