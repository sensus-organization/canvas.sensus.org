# frozen_string_literal: true

class SetReplicaIdentityOnJuryGradingRuns < ActiveRecord::Migration[7.2]
  tag :predeploy

  def up
    return unless connection.index_name_exists?(:jury_grading_runs, "index_jury_grading_runs_replica_identity")

    set_replica_identity :jury_grading_runs
  end
end
