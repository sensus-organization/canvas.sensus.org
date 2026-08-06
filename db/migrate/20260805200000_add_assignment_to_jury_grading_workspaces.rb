# frozen_string_literal: true

class AddAssignmentToJuryGradingWorkspaces < ActiveRecord::Migration[7.2]
  tag :predeploy
  disable_ddl_transaction!

  def up
    add_reference :jury_grading_workspaces,
                  :assignment,
                  foreign_key: { to_table: :assignments, on_delete: :cascade },
                  null: true,
                  index: false,
                  if_not_exists: true
    JuryGradingWorkspace.reset_column_information

    JuryGradingWorkspace.distinct.pluck(:course_id).each do |course_id|
      candidates = Assignment.active.where(context_type: "Course", context_id: course_id, jury_calibrated_grading: true).to_a
      next if candidates.empty?

      graded = ModeratedGrading::ProvisionalGrade.joins(:submission)
                                                 .where(submissions: { assignment_id: candidates.map(&:id) })
                                                 .group("submissions.assignment_id").count
      target = candidates.max_by { |assignment| [graded[assignment.id].to_i, -assignment.id] }
      JuryGradingWorkspace.where(course_id:, assignment_id: nil).update_all(assignment_id: target.id)
    end

    remove_index :jury_grading_workspaces, column: %i[assignment_id juror_id], algorithm: :concurrently, if_exists: true
    # rubocop:disable Migration/NonTransactional -- the remove_index above makes this idempotent; if_not_exists would silently keep an INVALID index from an interrupted build
    add_index :jury_grading_workspaces, %i[assignment_id juror_id], unique: true, algorithm: :concurrently
    # rubocop:enable Migration/NonTransactional
    remove_index :jury_grading_workspaces, column: %i[course_id juror_id], algorithm: :concurrently, if_exists: true
  end

  def down
    remove_index :jury_grading_workspaces, column: %i[assignment_id juror_id], algorithm: :concurrently, if_exists: true
    remove_reference :jury_grading_workspaces, :assignment, if_exists: true
    add_index :jury_grading_workspaces, %i[course_id juror_id], algorithm: :concurrently, if_not_exists: true
  end
end
