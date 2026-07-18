# frozen_string_literal: true

module JuryGrading
  class WorkspaceService
    ROLE_NAME = "Jury"
    ROLE_PREFIX = "jury:"

    def initialize(course:)
      @course = course
    end

    def ensure!
      @course.with_lock do
        jury_enrollments.each_with_object({ created: [], existing: [], invalid: [] }) do |enrollment, result|
          jury = enrollment.user
          workspace = JuryGradingWorkspace.find_by(course: @course, juror: jury)
          if workspace&.group_category&.deleted_at.present?
            workspace.destroy!
            workspace = nil
          end
          category = workspace&.group_category || legacy_category_for(jury)
          if category && category.deleted_at.nil? && category.groups.active.one?
            create_workspace!(jury, category) unless workspace
            clear_legacy_marker(category)
            result[:existing] << jury
          elsif category.present? || workspace.present?
            result[:invalid] << jury
          else
            category = @course.group_categories.create!(name: "Jury: #{jury.name} (#{jury.id})")
            category.groups.create!(name: category.name, context: @course)
            create_workspace!(jury, category)
            result[:created] << jury
          end
        end
      end
    end

    private

    def legacy_category_for(jury)
      @course.group_categories.active.find_by(role: category_role(jury)) ||
        @course.group_categories.active.find_by(sis_source_id: category_role(jury))
    end

    def create_workspace!(jury, category)
      JuryGradingWorkspace.create!(
        course: @course,
        juror: jury,
        group_category: category,
        root_account_id: @course.root_account_id
      )
    end

    def clear_legacy_marker(category)
      return unless category_role_from_category(category).to_s.start_with?(ROLE_PREFIX)

      category.update_columns(role: nil, sis_source_id: nil)
    end

    def category_role_from_category(category)
      category.role.to_s.start_with?(ROLE_PREFIX) ? category.role : category.sis_source_id
    end

    def category_role(jury)
      "#{ROLE_PREFIX}#{jury.id}"
    end

    def jury_enrollments
      @course.all_enrollments.active.joins(:role).where(enrollments: { type: "TaEnrollment" }, roles: { name: ROLE_NAME })
    end
  end
end
