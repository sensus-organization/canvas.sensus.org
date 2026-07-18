# frozen_string_literal: true

module JuryGrading
  class Scope
    def initialize(assignment:, user:)
      @assignment = assignment
      @user = user
    end

    def group
      return @group if defined?(@group)

      workspace = JuryGradingWorkspace.find_by(course: @assignment.context, juror: @user)
      category = workspace&.group_category ||
                 @assignment.context.group_categories.active.find_by(role: category_role) ||
                 @assignment.context.group_categories.active.find_by(sis_source_id: category_role)
      @group = category&.groups&.active&.sole
    rescue ActiveRecord::RecordNotFound, ActiveRecord::SoleRecordExceeded
      @group = nil
    end

    def jury?
      jury_user? && group.present?
    end

    def grading_open?
      jury? && !@assignment.grades_published? && @assignment.published_jury_grading_run_id.blank?
    end

    def jury_user?
      return false unless @assignment.jury_calibrated_grading?

      @assignment.context.all_enrollments.active.joins(:role)
                 .where(user_id: @user.id, enrollments: { type: "TaEnrollment" }, roles: { name: WorkspaceService::ROLE_NAME })
                 .exists?
    end

    def permits_submission?(submission)
      return true unless jury_user?

      group&.group_memberships&.active&.where(user_id: submission.user_id)&.exists? || false
    end

    private

    def category_role
      "#{WorkspaceService::ROLE_PREFIX}#{@user.id}"
    end
  end
end
