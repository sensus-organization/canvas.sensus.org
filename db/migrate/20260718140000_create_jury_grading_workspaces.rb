# frozen_string_literal: true

class CreateJuryGradingWorkspaces < ActiveRecord::Migration[7.2]
  tag :predeploy

  def up
    create_table :jury_grading_workspaces do |t|
      t.references :root_account, null: false, foreign_key: { to_table: :accounts }, index: false
      t.references :course, null: false, foreign_key: true
      t.references :juror, null: false, foreign_key: { to_table: :users }
      t.references :group_category, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.timestamps

      t.index %i[course_id juror_id], unique: true
      t.replica_identity_index
    end

    GroupCategory.where("role LIKE 'jury:%' OR sis_source_id LIKE 'jury:%'").find_each do |category|
      marker = category.role.to_s.start_with?("jury:") ? category.role : category.sis_source_id
      course = Course.find_by(id: category.context_id) if category.context_type == "Course"
      juror_id = marker.delete_prefix("jury:").to_i
      next unless course && juror_id.positive? && User.exists?(juror_id)

      workspace = JuryGradingWorkspace.find_or_create_by!(course:, juror_id:) do |workspace|
        workspace.root_account_id = course.root_account_id
        workspace.group_category = category
      end
      category.update_columns(role: nil, sis_source_id: nil) if workspace.group_category_id == category.id
    end
  end

  def down
    drop_table :jury_grading_workspaces
  end
end
