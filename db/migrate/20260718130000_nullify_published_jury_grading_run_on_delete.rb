# frozen_string_literal: true

class NullifyPublishedJuryGradingRunOnDelete < ActiveRecord::Migration[7.2]
  tag :predeploy
  disable_ddl_transaction!

  def up
    remove_foreign_key :assignments, :jury_grading_runs, column: :published_jury_grading_run_id
    add_foreign_key :assignments, :jury_grading_runs, column: :published_jury_grading_run_id, on_delete: :nullify, delay_validation: true
  end

  def down
    remove_foreign_key :assignments, :jury_grading_runs, column: :published_jury_grading_run_id
    add_foreign_key :assignments, :jury_grading_runs, column: :published_jury_grading_run_id
  end
end
