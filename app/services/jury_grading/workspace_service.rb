# frozen_string_literal: true

module JuryGrading
  class WorkspaceService
    ROLE_NAME = "Jury"
    LABEL_LIMIT = 40

    def initialize(assignment:, label: nil)
      @assignment = assignment
      @course = assignment.context
      @label = label.to_s.strip.presence
    end

    def self.jury_user_ids(course)
      course.all_enrollments.active.joins(:role)
            .where(enrollments: { type: "TaEnrollment" }, roles: { name: ROLE_NAME })
            .distinct.pluck(:user_id)
    end

    def ensure!(juror_ids: nil)
      ids = self.class.jury_user_ids(@course)
      ids &= Array.wrap(juror_ids).filter_map { |id| Integer(id, exception: false) } unless juror_ids.nil?
      jurors = User.where(id: ids).to_a

      result = @course.with_lock do
        jurors.each_with_object({ created: [], existing: [], invalid: [] }) do |jury, outcome|
          workspace = JuryGradingWorkspace.find_by(assignment: @assignment, juror: jury)
          if workspace&.group_category&.deleted_at.present?
            workspace.destroy!
            workspace = nil
          end
          category = workspace&.group_category

          if category && category.groups.active.one?
            outcome[:existing] << jury
          elsif category.present?
            outcome[:invalid] << jury
          else
            category = @course.group_categories.create!(name: category_name(jury))
            category.groups.create!(name: category.name, context: @course)
            create_workspace!(jury, category)
            outcome[:created] << jury
          end
        end
      end

      @assignment.save! if result[:created].any?
      result
    end

    private

    def create_workspace!(jury, category)
      JuryGradingWorkspace.create!(
        course: @course,
        assignment: @assignment,
        juror: jury,
        group_category: category,
        root_account_id: @course.root_account_id
      )
    end

    def category_name(jury)
      base = compose(label, jury)
      return base unless @course.group_categories.where(name: base).exists?

      compose("#{label} ##{@assignment.id}", jury)
    end

    def compose(prefix, jury)
      "#{prefix} — #{jury.name} (#{jury.id})".truncate(GroupCategory.maximum_string_length)
    end

    def label
      (@label || @assignment.title.to_s).truncate(LABEL_LIMIT)
    end
  end
end
