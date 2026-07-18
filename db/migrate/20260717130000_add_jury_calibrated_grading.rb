# frozen_string_literal: true

class AddJuryCalibratedGrading < ActiveRecord::Migration[7.2]
  tag :predeploy

  def change
    change_table :assignments, bulk: true do |t|
      t.boolean :jury_calibrated_grading, default: false, null: false
    end

    create_table :jury_grading_runs do |t|
      t.references :root_account, null: false, foreign_key: { to_table: :accounts }, index: false
      t.references :assignment, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :workflow_state, null: false, default: "queued"
      t.string :algorithm_version, null: false
      t.jsonb :settings, null: false, default: {}
      t.jsonb :input, null: false, default: {}
      t.jsonb :results, null: false, default: {}
      t.timestamps precision: nil
      t.replica_identity_index
    end
    add_reference :assignments,
                  :published_jury_grading_run,
                  foreign_key: { to_table: :jury_grading_runs, on_delete: :nullify },
                  index: true
  end
end
