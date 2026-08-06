# frozen_string_literal: true

module JuryGrading
  class Scope
    def initialize(assignment:, user:)
      @assignment = assignment
      @user = user
    end

    def group
      return @group if defined?(@group)

      workspace = JuryGradingWorkspace.find_by(assignment: @assignment, juror: @user)
      @group = workspace&.group_category&.groups&.active&.sole
    rescue ActiveRecord::RecordNotFound, ActiveRecord::SoleRecordExceeded
      @group = nil
    end

    def jury?
      jury_assignment? && group.present?
    end

    def grading_open?
      jury? && !@assignment.grades_published? && @assignment.published_jury_grading_run_id.blank?
    end

    def jury_assignment?
      jury_user? && @assignment.jury_calibrated_grading?
    end

    def jury_user?
      return @jury_user if defined?(@jury_user)

      @jury_user = @assignment.context.all_enrollments.active.joins(:role)
                              .where(user_id: @user.id, enrollments: { type: "TaEnrollment" }, roles: { name: WorkspaceService::ROLE_NAME })
                              .exists?
    end

    def permits_submission?(submission)
      return true unless jury_user?
      return false unless jury_assignment?

      group&.group_memberships&.active&.where(user_id: submission.user_id)&.exists? || false
    end
  end
end
